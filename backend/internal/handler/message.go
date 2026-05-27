package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/service"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// ── Handler ───────────────────────────────────────────────────────────────────

type MessageHandler struct {
	service *service.MessageService
	appHub  *AppHub
}

func NewMessageHandler(service *service.MessageService, appHub *AppHub) *MessageHandler {
	return &MessageHandler{service: service, appHub: appHub}
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

	var types []string
	if raw := ctx.Query("types"); raw != "" {
		types = strings.Split(raw, ",")
	}

	messages, err := h.service.GetMessages(chatID, beforeID, limit, types)
	if err != nil {
		log.Printf("get messages error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	result := make([]dto.MessageDTO, len(messages))
	for i, m := range messages {
		result[i] = dto.ToMessageDTO(m)
	}

	resp := dto.GetMessagesResponse{Messages: result}

	// Для DM добавляем курсор партнёра, чтобы фронт мог вычислить статус сообщений.
	if isDM, _ := h.service.IsDMChat(chatID); isDM {
		if cursor, err := h.service.GetPartnerCursor(chatID, userID); err == nil {
			resp.PartnerCursor = &dto.PartnerCursorDTO{
				LastReadMessageID:      cursor.LastReadMessageID,
				LastDeliveredMessageID: cursor.LastDeliveredMessageID,
			}
		}
	}

	ctx.JSON(http.StatusOK, resp)
}

// SendMessage сохраняет сообщение в БД, рассылает участникам чата и уведомляет партнёра.
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

	msg, err := h.service.SendMessage(chatID, userID, req.Content, req.Type, req.FileName, req.FileSize, req.Caption)
	if err != nil {
		log.Printf("send message error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	result := dto.ToMessageDTO(msg)

	// Рассылаем в чат всем кроме отправителя (он получил через REST-ответ)
	if n, err := dto.NewNotification("chat_message", result); err == nil {
		if data, err := json.Marshal(n); err == nil {
			h.appHub.BroadcastToChat(chatID, userID, data)
		}
	}

	// Уведомляем всех участников чата для обновления chat-list (работает и для DM и для групп)
	if memberIDs, err := h.service.GetChatMemberIDs(chatID); err == nil {
		if n, err := dto.NewNotification("new_message", dto.NewMessagePayload{
			MessageID: msg.ID,
			ChatID:    chatID,
			SenderID:  userID,
			Content:   req.Content,
			CreatedAt: msg.CreatedAt,
		}); err == nil {
			for _, mid := range memberIDs {
				if mid != userID {
					h.appHub.NotifyUser(mid, n)
				}
			}
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
