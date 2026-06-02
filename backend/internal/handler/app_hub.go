package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/config"
	"cove/internal/model"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"path"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
)

// ── Константы и апгрейдер ────────────────────────────────────────────────────

const (
	writeWait       = 10 * time.Second
	pongWait        = 60 * time.Second
	pingPeriod      = (pongWait * 9) / 10
	typingDebounce  = 3 * time.Second
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			// прямые WS-соединения без Origin (например, нативные клиенты) — разрешаем
			return true
		}
		allowed := config.GetConfig().AllowedOrigins
		for _, pattern := range allowed {
			// поддерживаем wildcards через path.Match (e.g. "http://localhost:*")
			matched, err := path.Match(strings.ToLower(pattern), strings.ToLower(origin))
			if err == nil && matched {
				return true
			}
		}
		log.Printf("ws: rejected origin %q", origin)
		return false
	},
}

// ── Типы сообщений хаба ───────────────────────────────────────────────────────

type broadcastMsg struct {
	chatID        uint
	excludeUserID uint
	data          []byte
}

type notifyMsg struct {
	userID uint
	data   []byte
}

type subMsg struct {
	client *AppClient
	chatID uint
}

type presenceQueryMsg struct {
	userIDs []uint
	resp    chan map[uint]bool
}

// ── AppHub ────────────────────────────────────────────────────────────────────

// AppHub управляет всеми WS-соединениями: уведомления (по userID) + чаты (по chatID).
// Один экземпляр на весь сервер, работает в отдельной горутине.
type AppHub struct {
	users       map[uint]map[*AppClient]bool // user_id → клиенты
	chats       map[uint]map[*AppClient]bool // chat_id → подписанные клиенты
	broadcast   chan broadcastMsg            // рассылка в чат (кроме отправителя)
	notify      chan notifyMsg               // личное уведомление пользователю
	subscribe   chan subMsg
	unsubscribe chan subMsg
	register    chan *AppClient
	unregister  chan *AppClient
	isMember      func(chatID, userID uint) (bool, error)
	markDelivered func(chatID, userID, messageID uint) (senderID uint, err error)
	markRead      func(chatID, userID, messageID uint) (senderID uint, err error)
	getFriendIDs  func(userID uint) ([]uint, error)
	updateLastSeen func(userID uint) error
	presenceQuery chan presenceQueryMsg

	// typingMu защищает typingLastSent от конкурентного доступа из readPump-горутин.
	typingMu       sync.Mutex
	typingLastSent map[uint]map[uint]time.Time // chatID → userID → last sent
}

func NewAppHub(
	isMember func(chatID, userID uint) (bool, error),
	markDelivered func(chatID, userID, messageID uint) (uint, error),
	markRead func(chatID, userID, messageID uint) (uint, error),
	getFriendIDs func(userID uint) ([]uint, error),
	updateLastSeen func(userID uint) error,
) *AppHub {
	return &AppHub{
		users:          make(map[uint]map[*AppClient]bool),
		chats:          make(map[uint]map[*AppClient]bool),
		broadcast:      make(chan broadcastMsg, 256),
		notify:         make(chan notifyMsg, 256),
		subscribe:      make(chan subMsg, 32),
		unsubscribe:    make(chan subMsg, 32),
		register:       make(chan *AppClient),
		unregister:     make(chan *AppClient),
		presenceQuery:  make(chan presenceQueryMsg, 16),
		isMember:       isMember,
		markDelivered:  markDelivered,
		markRead:       markRead,
		getFriendIDs:   getFriendIDs,
		updateLastSeen: updateLastSeen,
		typingLastSent: make(map[uint]map[uint]time.Time),
	}
}

func (h *AppHub) Run() {
	for {
		select {
		case c := <-h.register:
			firstConn := h.users[c.userID] == nil
			if firstConn {
				h.users[c.userID] = make(map[*AppClient]bool)
			}
			h.users[c.userID][c] = true
			if firstConn {
				go h.broadcastPresence(c.userID, true)
			}

		case c := <-h.unregister:
			if room, ok := h.users[c.userID]; ok {
				if _, ok := room[c]; ok {
					delete(room, c)
					close(c.send)
					if len(room) == 0 {
						delete(h.users, c.userID)
						go h.broadcastPresence(c.userID, false)
						if h.updateLastSeen != nil {
							go func(uid uint) {
								if err := h.updateLastSeen(uid); err != nil {
									log.Printf("updateLastSeen user=%d: %v", uid, err)
								}
							}(c.userID)
						}
					}
				}
			}
			// Удалить из всех чатов
			for chatID, room := range h.chats {
				delete(room, c)
				if len(room) == 0 {
					delete(h.chats, chatID)
				}
			}

		case msg := <-h.subscribe:
			if h.chats[msg.chatID] == nil {
				h.chats[msg.chatID] = make(map[*AppClient]bool)
			}
			h.chats[msg.chatID][msg.client] = true

		case msg := <-h.unsubscribe:
			if room, ok := h.chats[msg.chatID]; ok {
				delete(room, msg.client)
				if len(room) == 0 {
					delete(h.chats, msg.chatID)
				}
			}

		case msg := <-h.broadcast:
			if room, ok := h.chats[msg.chatID]; ok {
				for c := range room {
					if c.userID == msg.excludeUserID {
						continue
					}
					select {
					case c.send <- msg.data:
					default:
						close(c.send)
						delete(room, c)
					}
				}
			}

		case msg := <-h.notify:
			if room, ok := h.users[msg.userID]; ok {
				for c := range room {
					select {
					case c.send <- msg.data:
					default:
						close(c.send)
						delete(room, c)
					}
				}
			}

		case q := <-h.presenceQuery:
			result := make(map[uint]bool, len(q.userIDs))
			for _, id := range q.userIDs {
				result[id] = len(h.users[id]) > 0
			}
			q.resp <- result
		}
	}
}

// IsOnlineMany возвращает карту userID → онлайн для запрошенных пользователей.
func (h *AppHub) IsOnlineMany(userIDs []uint) map[uint]bool {
	resp := make(chan map[uint]bool, 1)
	h.presenceQuery <- presenceQueryMsg{userIDs: userIDs, resp: resp}
	return <-resp
}

// broadcastPresence рассылает статус присутствия всем онлайн-друзьям пользователя.
func (h *AppHub) broadcastPresence(userID uint, online bool) {
	if h.getFriendIDs == nil {
		return
	}
	friendIDs, err := h.getFriendIDs(userID)
	if err != nil {
		log.Printf("broadcastPresence: getFriendIDs user=%d: %v", userID, err)
		return
	}
	n, err := dto.NewNotification("user_presence", dto.UserPresencePayload{
		UserID:   userID,
		IsOnline: online,
	})
	if err != nil {
		return
	}
	for _, fid := range friendIDs {
		h.NotifyUser(fid, n)
	}
}

// BroadcastToChat рассылает данные всем подписчикам чата, кроме отправителя.
// excludeUserID == 0 означает "рассылать всем".
func (h *AppHub) BroadcastToChat(chatID, senderID uint, data []byte) {
	select {
	case h.broadcast <- broadcastMsg{chatID: chatID, excludeUserID: senderID, data: data}:
	default:
		log.Printf("app hub broadcast channel full for chat %d", chatID)
	}
}

// NotifyUser отправляет уведомление пользователю по всем его активным соединениям.
func (h *AppHub) NotifyUser(userID uint, n dto.NotificationDTO) {
	data, err := json.Marshal(n)
	if err != nil {
		log.Printf("app hub marshal error: %v", err)
		return
	}
	select {
	case h.notify <- notifyMsg{userID: userID, data: data}:
	default:
		log.Printf("app hub notify channel full for user %d", userID)
	}
}

// broadcastTyping отправляет typing-нотификацию в чат с дебаунсом (не чаще 1 раза в 3 сек).
func (h *AppHub) broadcastTyping(chatID, userID uint, username string) {
	h.typingMu.Lock()
	if h.typingLastSent[chatID] == nil {
		h.typingLastSent[chatID] = make(map[uint]time.Time)
	}
	last := h.typingLastSent[chatID][userID]
	if time.Since(last) < typingDebounce {
		h.typingMu.Unlock()
		return
	}
	h.typingLastSent[chatID][userID] = time.Now()
	h.typingMu.Unlock()

	n, err := dto.NewNotification("typing", dto.TypingPayload{
		ChatID:   chatID,
		UserID:   userID,
		Username: username,
	})
	if err != nil {
		return
	}
	data, err := json.Marshal(n)
	if err != nil {
		return
	}
	h.BroadcastToChat(chatID, userID, data)
}

// ServeWS обрабатывает GET /ws?token= — единственный WS-эндпоинт.
func (h *AppHub) ServeWS(ctx *gin.Context) {
	claims, err := parseTokenClaims(ctx.Query("token"))
	if err != nil {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Недействительный токен"})
		return
	}

	conn, err := upgrader.Upgrade(ctx.Writer, ctx.Request, nil)
	if err != nil {
		log.Printf("ws upgrade error: %v", err)
		return
	}

	c := &AppClient{
		hub:      h,
		userID:   claims.UserID,
		username: claims.Username,
		conn:     conn,
		send:     make(chan []byte, 256),
	}
	h.register <- c
	go c.writePump()
	go c.readPump()

	// Сразу уведомляем клиента что соединение установлено — клиент не имеет
	// отдельного «connected» колбэка в WebSocket API, поэтому шлём явное сообщение.
	if data, err := json.Marshal(map[string]string{"type": "connected"}); err == nil {
		select {
		case c.send <- data:
		default:
		}
	}
}

// ── AppClient ─────────────────────────────────────────────────────────────────

type AppClient struct {
	hub      *AppHub
	userID   uint
	username string
	conn     *websocket.Conn
	send     chan []byte
}

func (c *AppClient) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})
	for {
		_, msg, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("ws read error user=%d: %v", c.userID, err)
			}
			break
		}
		var cmd struct {
			Type      string `json:"type"`
			ChatID    uint   `json:"chat_id"`
			MessageID uint   `json:"message_id"`
		}
		if err := json.Unmarshal(msg, &cmd); err != nil {
			continue
		}
		switch cmd.Type {
		case "subscribe_chat":
			ok, _ := c.hub.isMember(cmd.ChatID, c.userID)
			if ok {
				c.hub.subscribe <- subMsg{client: c, chatID: cmd.ChatID}
			}
		case "unsubscribe_chat":
			c.hub.unsubscribe <- subMsg{client: c, chatID: cmd.ChatID}
		case "typing":
			if cmd.ChatID == 0 {
				continue
			}
			go c.hub.broadcastTyping(cmd.ChatID, c.userID, c.username)
		case "ack_delivered":
			if cmd.ChatID == 0 || cmd.MessageID == 0 {
				continue
			}
			senderID, err := c.hub.markDelivered(cmd.ChatID, c.userID, cmd.MessageID)
			if err != nil {
				log.Printf("mark delivered error user=%d msg=%d: %v", c.userID, cmd.MessageID, err)
				continue
			}
			if n, err := dto.NewNotification("message_delivered", dto.MessageDeliveredPayload{
				ChatID:      cmd.ChatID,
				MessageID:   cmd.MessageID,
				DeliveredAt: time.Now(),
			}); err == nil {
				c.hub.NotifyUser(senderID, n)
			}
		case "mark_read":
			if cmd.ChatID == 0 || cmd.MessageID == 0 {
				continue
			}
			senderID, err := c.hub.markRead(cmd.ChatID, c.userID, cmd.MessageID)
			if err != nil {
				log.Printf("mark read error user=%d msg=%d: %v", c.userID, cmd.MessageID, err)
				continue
			}
			if n, err := dto.NewNotification("message_read", dto.MessageReadPayload{
				ChatID:            cmd.ChatID,
				LastReadMessageID: cmd.MessageID,
				ReadAt:            time.Now(),
			}); err == nil {
				c.hub.NotifyUser(senderID, n)
			}
		}
	}
}

func (c *AppClient) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()
	for {
		select {
		case msg, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// parseTokenClaims разбирает JWT из строки — для WS-соединений,
// где токен передаётся через query-параметр ?token=.
func parseTokenClaims(tokenStr string) (*model.CustomClaims, error) {
	if tokenStr == "" {
		return nil, fmt.Errorf("empty token")
	}
	cfg := config.GetConfig()
	claims := &model.CustomClaims{}
	token, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return []byte(cfg.JwtSecret), nil
	})
	if err != nil || !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}
	return claims, nil
}
