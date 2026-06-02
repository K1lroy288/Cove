package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/model"
	"cove/internal/service"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

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

	result, err := h.service.EnrichMessages(messages, userID)
	if err != nil {
		log.Printf("enrich messages error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
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

	msg, err := h.service.SendMessage(
		chatID, userID,
		req.Content, req.Type,
		req.FileName, req.FileSize, req.Caption,
		req.ReplyToID,
		req.ForwardedFromID, req.ForwardedFromUsername,
	)
	if err != nil {
		log.Printf("send message error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	enriched, err := h.service.EnrichMessages([]model.Message{msg}, userID)
	if err != nil || len(enriched) == 0 {
		log.Printf("enrich sent message error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}
	result := enriched[0]

	// Рассылаем в чат всем кроме отправителя (он получил через REST-ответ)
	if n, err := dto.NewNotification("chat_message", result); err == nil {
		if data, err := json.Marshal(n); err == nil {
			h.appHub.BroadcastToChat(chatID, userID, data)
		}
	}

	// Уведомляем всех участников чата для обновления chat-list
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

// EditMessage редактирует текст сообщения.
// PATCH /chat/:id/messages/:msg_id
func (h *MessageHandler) EditMessage(ctx *gin.Context) {
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

	msgID, err := parseUintParam(ctx, "msg_id")
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный msg_id"})
		return
	}

	var req dto.EditMessageRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	msg, err := h.service.EditMessage(msgID, userID, req.Content)
	if err != nil {
		log.Printf("edit message error: %v", err)
		ctx.JSON(http.StatusForbidden, gin.H{"message": "Сообщение не найдено или нет доступа"})
		return
	}

	editedAt := time.Now()
	if msg.EditedAt != nil {
		editedAt = *msg.EditedAt
	}
	if n, err := dto.NewNotification("message_edited", dto.MessageEditedPayload{
		ChatID:     chatID,
		MessageID:  msgID,
		NewContent: msg.Content,
		EditedAt:   editedAt,
	}); err == nil {
		if data, err := json.Marshal(n); err == nil {
			// Рассылаем всем в чате, включая отправителя (чтобы обновить у него тоже)
			h.appHub.BroadcastToChat(chatID, 0, data)
		}
	}

	ctx.JSON(http.StatusOK, dto.ToMessageDTO(msg))
}

// DeleteMessage удаляет сообщение (soft-delete).
// DELETE /chat/:id/messages/:msg_id
func (h *MessageHandler) DeleteMessage(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	msgID, err := parseUintParam(ctx, "msg_id")
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный msg_id"})
		return
	}

	chatID, err := h.service.DeleteMessage(msgID, userID)
	if err != nil {
		log.Printf("delete message error: %v", err)
		ctx.JSON(http.StatusForbidden, gin.H{"message": "Сообщение не найдено или нет доступа"})
		return
	}

	if n, err := dto.NewNotification("message_deleted", dto.MessageDeletedPayload{
		ChatID:    chatID,
		MessageID: msgID,
	}); err == nil {
		if data, err := json.Marshal(n); err == nil {
			h.appHub.BroadcastToChat(chatID, 0, data)
		}
	}

	ctx.Status(http.StatusNoContent)
}

// ToggleReaction добавляет или убирает реакцию на сообщение.
// POST /chat/:id/messages/:msg_id/reactions
func (h *MessageHandler) ToggleReaction(ctx *gin.Context) {
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

	msgID, err := parseUintParam(ctx, "msg_id")
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный msg_id"})
		return
	}

	var req struct {
		Emoji string `json:"emoji" binding:"required"`
	}
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Укажите emoji"})
		return
	}

	reactions, err := h.service.ToggleReaction(msgID, userID, req.Emoji)
	if err != nil {
		log.Printf("toggle reaction error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	groups := aggregateReactionGroups(reactions, userID)

	if n, err := dto.NewNotification("reaction_updated", dto.ReactionUpdatedPayload{
		ChatID:    chatID,
		MessageID: msgID,
		Reactions: groups,
	}); err == nil {
		if data, err := json.Marshal(n); err == nil {
			h.appHub.BroadcastToChat(chatID, 0, data)
		}
	}

	ctx.JSON(http.StatusOK, gin.H{"reactions": groups})
}

// SearchMessages ищет сообщения по тексту внутри чата.
// GET /chat/:id/messages/search?q=<text>&limit=<n>&before=<id>
func (h *MessageHandler) SearchMessages(ctx *gin.Context) {
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

	query := ctx.Query("q")
	if query == "" {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Параметр q обязателен"})
		return
	}

	limit := 20
	if raw := ctx.Query("limit"); raw != "" {
		if v, err := strconv.Atoi(raw); err == nil && v > 0 && v <= 50 {
			limit = v
		}
	}

	var beforeID *uint
	if raw := ctx.Query("before"); raw != "" {
		if v, err := strconv.ParseUint(raw, 10, 64); err == nil {
			id := uint(v)
			beforeID = &id
		}
	}

	messages, err := h.service.SearchMessages(chatID, query, limit, beforeID)
	if err != nil {
		log.Printf("search messages error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	result := make([]dto.MessageDTO, len(messages))
	for i, m := range messages {
		result[i] = dto.ToMessageDTO(m)
	}

	ctx.JSON(http.StatusOK, gin.H{"messages": result})
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func parseChatID(ctx *gin.Context) (uint, error) {
	v, err := strconv.ParseUint(ctx.Param("id"), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid chat id")
	}
	return uint(v), nil
}

func aggregateReactionGroups(reactions []model.MessageReaction, myUserID uint) []dto.ReactionGroupDTO {
	counts := make(map[string]int)
	mine := make(map[string]bool)
	for _, r := range reactions {
		counts[r.Emoji]++
		if r.UserID == myUserID {
			mine[r.Emoji] = true
		}
	}
	result := make([]dto.ReactionGroupDTO, 0, len(counts))
	for emoji, count := range counts {
		result = append(result, dto.ReactionGroupDTO{
			Emoji:   emoji,
			Count:   count,
			HasMine: mine[emoji],
		})
	}
	return result
}
