package handler

import (
	dto "cove/internal/DTO"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

type userBroadcastMsg struct {
	userID uint
	data   []byte
}

// UserHub управляет персональными WS-каналами пользователей для уведомлений.
// Один экземпляр на весь сервер, работает в отдельной горутине.
type UserHub struct {
	clients    map[uint]map[*UserClient]bool // user_id → набор клиентов
	broadcast  chan userBroadcastMsg
	register   chan *UserClient
	unregister chan *UserClient
}

func NewUserHub() *UserHub {
	return &UserHub{
		clients:    make(map[uint]map[*UserClient]bool),
		broadcast:  make(chan userBroadcastMsg, 256),
		register:   make(chan *UserClient),
		unregister: make(chan *UserClient),
	}
}

func (h *UserHub) Run() {
	for {
		select {
		case c := <-h.register:
			if h.clients[c.userID] == nil {
				h.clients[c.userID] = make(map[*UserClient]bool)
			}
			h.clients[c.userID][c] = true

		case c := <-h.unregister:
			if room, ok := h.clients[c.userID]; ok {
				if _, ok := room[c]; ok {
					delete(room, c)
					close(c.send)
					if len(room) == 0 {
						delete(h.clients, c.userID)
					}
				}
			}

		case msg := <-h.broadcast:
			if room, ok := h.clients[msg.userID]; ok {
				for c := range room {
					select {
					case c.send <- msg.data:
					default:
						close(c.send)
						delete(room, c)
					}
				}
			}
		}
	}
}

// NotifyUser отправляет уведомление пользователю по всем его активным соединениям.
// Non-blocking: при переполнении канала уведомление отбрасывается с логом.
func (h *UserHub) NotifyUser(userID uint, n dto.NotificationDTO) {
	data, err := json.Marshal(n)
	if err != nil {
		log.Printf("user hub marshal error: %v", err)
		return
	}
	select {
	case h.broadcast <- userBroadcastMsg{userID: userID, data: data}:
	default:
		log.Printf("user hub broadcast channel full for user %d", userID)
	}
}

// ServeWS обрабатывает GET /ws?token= — персональный канал уведомлений.
func (h *UserHub) ServeWS(ctx *gin.Context) {
	claims, err := parseTokenClaims(ctx.Query("token"))
	if err != nil {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Недействительный токен"})
		return
	}

	conn, err := upgrader.Upgrade(ctx.Writer, ctx.Request, nil)
	if err != nil {
		log.Printf("user ws upgrade error: %v", err)
		return
	}

	c := &UserClient{
		hub:    h,
		userID: claims.UserID,
		conn:   conn,
		send:   make(chan []byte, 256),
	}
	h.register <- c
	go c.writePump()
	go c.readPump()
}

// ── UserClient ────────────────────────────────────────────────────────────────

type UserClient struct {
	hub    *UserHub
	userID uint
	conn   *websocket.Conn
	send   chan []byte
}

func (c *UserClient) readPump() {
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
				log.Printf("user ws read error: %v", err)
			}
			break
		}
	}
}

func (c *UserClient) writePump() {
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
