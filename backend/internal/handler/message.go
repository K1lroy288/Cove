package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/config"
	"cove/internal/model"
	"cove/internal/service"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
)

// ── Hub ──────────────────────────────────────────────────────────────────────

type broadcastMsg struct {
	chatID uint
	data   []byte
}

// Hub управляет всеми WS-соединениями с маршрутизацией по chat_id.
// Один экземпляр на весь сервер, работает в отдельной горутине.
type Hub struct {
	clients    map[uint]map[*Client]bool // chat_id → набор клиентов
	broadcast  chan broadcastMsg
	register   chan *Client
	unregister chan *Client
}

func NewHub() *Hub {
	return &Hub{
		broadcast:  make(chan broadcastMsg, 256),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		clients:    make(map[uint]map[*Client]bool),
	}
}

// Run — главный цикл хаба, запускается в горутине: go hub.Run()
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			if h.clients[client.chatID] == nil {
				h.clients[client.chatID] = make(map[*Client]bool)
			}
			h.clients[client.chatID][client] = true

		case client := <-h.unregister:
			if room, ok := h.clients[client.chatID]; ok {
				if _, ok := room[client]; ok {
					delete(room, client)
					close(client.send)
					if len(room) == 0 {
						delete(h.clients, client.chatID)
					}
				}
			}

		case msg := <-h.broadcast:
			if room, ok := h.clients[msg.chatID]; ok {
				for client := range room {
					select {
					case client.send <- msg.data:
					default:
						// Канал клиента переполнен — он завис, отключаем
						close(client.send)
						delete(room, client)
					}
				}
			}
		}
	}
}

// ── Client ───────────────────────────────────────────────────────────────────

type Client struct {
	hub    *Hub
	chatID uint
	userID uint
	conn   *websocket.Conn
	send   chan []byte
}

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = (pongWait * 9) / 10
)

// readPump читает фреймы от клиента — нужен для ping/pong и обнаружения отключения.
// Входящие текстовые сообщения игнорируем: отправка идёт через REST POST /chat/:id/messages.
func (c *Client) readPump() {
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
		if _, _, err := c.conn.ReadMessage(); err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("ws read error: %v", err)
			}
			break
		}
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()
	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
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

// ── Handler ───────────────────────────────────────────────────────────────────

type MessageHandler struct {
	service *service.MessageService
	hub     *Hub
	userHub *UserHub
}

func NewMessageHandler(service *service.MessageService, hub *Hub, userHub *UserHub) *MessageHandler {
	return &MessageHandler{service: service, hub: hub, userHub: userHub}
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

// ServeWS апгрейдит соединение до WebSocket.
// JWT передаётся через query-параметр ?token= (заголовки недоступны после upgrade).
// GET /chat/:id/ws?token=<jwt>
func (h *MessageHandler) ServeWS(ctx *gin.Context) {
	chatID, err := parseChatID(ctx)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный chat_id"})
		return
	}

	claims, err := parseTokenClaims(ctx.Query("token"))
	if err != nil {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Недействительный токен"})
		return
	}

	isMember, err := h.service.IsChatMember(chatID, claims.UserID)
	if err != nil || !isMember {
		ctx.JSON(http.StatusForbidden, gin.H{"message": "Нет доступа к чату"})
		return
	}

	conn, err := upgrader.Upgrade(ctx.Writer, ctx.Request, nil)
	if err != nil {
		log.Printf("ws upgrade error: %v", err)
		return
	}

	client := &Client{
		hub:    h.hub,
		chatID: chatID,
		userID: claims.UserID,
		conn:   conn,
		send:   make(chan []byte, 256),
	}
	h.hub.register <- client
	go client.writePump()
	go client.readPump()
}

// GetMessages возвращает историю сообщений чата с cursor-based пагинацией.
// GET /chat/:id/messages?before=<id>&limit=<n>
func (h *MessageHandler) GetMessages(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	chatID, err := parseChatID(ctx)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный chat_id"})
		return
	}

	isMember, err := h.service.IsChatMember(chatID, userID)
	if err != nil || !isMember {
		ctx.JSON(http.StatusForbidden, gin.H{"message": "Нет доступа к чату"})
		return
	}

	var beforeID *uint
	if raw := ctx.Query("before"); raw != "" {
		if v, err := strconv.ParseUint(raw, 10, 64); err == nil {
			id := uint(v)
			beforeID = &id
		}
	}

	limit := 50
	if raw := ctx.Query("limit"); raw != "" {
		if v, err := strconv.Atoi(raw); err == nil && v > 0 && v <= 100 {
			limit = v
		}
	}

	messages, err := h.service.GetMessages(chatID, beforeID, limit)
	if err != nil {
		log.Printf("get messages error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	result := make([]dto.MessageDTO, len(messages))
	for i, m := range messages {
		result[i] = dto.ToMessageDTO(m)
	}
	ctx.JSON(http.StatusOK, result)
}

// SendMessage сохраняет сообщение в БД и рассылает всем участникам чата через WS.
// POST /chat/:id/messages
func (h *MessageHandler) SendMessage(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	chatID, err := parseChatID(ctx)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный chat_id"})
		return
	}

	isMember, err := h.service.IsChatMember(chatID, userID)
	if err != nil || !isMember {
		ctx.JSON(http.StatusForbidden, gin.H{"message": "Нет доступа к чату"})
		return
	}

	var req dto.SendMessageRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	msg, err := h.service.SendMessage(chatID, userID, req.Content, req.Type)
	if err != nil {
		log.Printf("send message error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	result := dto.ToMessageDTO(msg)

	if data, err := json.Marshal(result); err == nil {
		h.hub.broadcast <- broadcastMsg{chatID: chatID, data: data}
	}

	if partnerID, err := h.service.GetPartnerID(chatID, userID); err == nil {
		if n, err := dto.NewNotification("new_message", dto.NewMessagePayload{
			ChatID:    chatID,
			SenderID:  userID,
			Content:   req.Content,
			CreatedAt: msg.CreatedAt,
		}); err == nil {
			h.userHub.NotifyUser(partnerID, n)
		}
	}

	ctx.JSON(http.StatusCreated, result)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func parseChatID(ctx *gin.Context) (uint, error) {
	v, err := strconv.ParseUint(ctx.Param("id"), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid chat id")
	}
	return uint(v), nil
}

// parseTokenClaims разбирает JWT из строки — используется для WS-соединений,
// где токен передаётся через query-параметр, а не заголовок Authorization.
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
