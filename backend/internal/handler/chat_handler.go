package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/service"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

type ChatHandler struct {
	service *service.ChatService
	appHub  *AppHub
}

func NewChatHandler(s *service.ChatService, hub *AppHub) *ChatHandler {
	return &ChatHandler{service: s, appHub: hub}
}

// broadcastJSON сериализует уведомление и рассылает подписчикам чата.
func (h *ChatHandler) broadcastJSON(chatID uint, notif dto.NotificationDTO) {
	data, err := json.Marshal(notif)
	if err != nil {
		return
	}
	h.appHub.BroadcastToChat(chatID, 0, data)
}

// GetChats возвращает список чатов (DM и группы) текущего пользователя.
// GET /chat/
func (h *ChatHandler) GetChats(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	chats, err := h.service.GetChats(userID)
	if err != nil {
		log.Printf("get chats error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	ctx.JSON(http.StatusOK, chats)
}

// CreateChat создаёт DM-чат с другом или возвращает существующий.
// POST /chat/
func (h *ChatHandler) CreateChat(ctx *gin.Context) {
	myUserID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	var req dto.CreateChatRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	chat, isNew, err := h.service.CreateOrGetChat(myUserID, req.FriendID)
	if err != nil {
		if errors.Is(err, service.ErrNotFriends) {
			ctx.JSON(http.StatusForbidden, gin.H{"message": "Можно создать чат только с другом"})
			return
		}
		log.Printf("create chat error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	status := http.StatusOK
	if isNew {
		status = http.StatusCreated
	}
	ctx.JSON(status, chat)
}

// --- Группы ---

// CreateGroup создаёт новую группу.
// POST /groups/
func (h *ChatHandler) CreateGroup(ctx *gin.Context) {
	myID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	var req dto.CreateGroupRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	chatDTO, allMemberIDs, err := h.service.CreateGroup(myID, req)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrGroupTooSmall):
			ctx.JSON(http.StatusBadRequest, gin.H{"message": "Нужно минимум 3 участника"})
		case errors.Is(err, service.ErrGroupFull):
			ctx.JSON(http.StatusBadRequest, gin.H{"message": "Максимум 15 участников"})
		case errors.Is(err, service.ErrNotFriends):
			ctx.JSON(http.StatusForbidden, gin.H{"message": "Все участники должны быть вашими друзьями"})
		default:
			log.Printf("create group error: %v", err)
			ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		}
		return
	}

	notif, err := dto.NewNotification("group_created", dto.GroupCreatedPayload{
		ChatID:      chatDTO.ID,
		GroupName:   chatDTO.GroupName,
		GroupAvatar: chatDTO.GroupAvatar,
		CreatedBy:   myID,
	})
	if err == nil {
		for _, mid := range allMemberIDs {
			h.appHub.NotifyUser(mid, notif)
		}
	}

	ctx.JSON(http.StatusCreated, chatDTO)
}

// GetGroupMembers возвращает список участников группы.
// GET /groups/:id/members
func (h *ChatHandler) GetGroupMembers(ctx *gin.Context) {
	myID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}
	chatID, err := parseChatID(ctx)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный ID чата"})
		return
	}

	members, err := h.service.GetGroupMembers(chatID, myID)
	if err != nil {
		if errors.Is(err, service.ErrNotMember) {
			ctx.JSON(http.StatusForbidden, gin.H{"message": "Вы не участник этой группы"})
			return
		}
		log.Printf("get group members error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	ctx.JSON(http.StatusOK, members)
}

// AddMembers добавляет участников в группу (только admin).
// POST /groups/:id/members
func (h *ChatHandler) AddMembers(ctx *gin.Context) {
	myID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}
	chatID, err := parseChatID(ctx)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный ID чата"})
		return
	}

	var req dto.AddMembersRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	if err := h.service.AddMembers(chatID, myID, req.UserIDs); err != nil {
		switch {
		case errors.Is(err, service.ErrNotAdmin):
			ctx.JSON(http.StatusForbidden, gin.H{"message": "Только администратор может добавлять участников"})
		case errors.Is(err, service.ErrGroupFull):
			ctx.JSON(http.StatusBadRequest, gin.H{"message": "Достигнут лимит участников (15)"})
		case errors.Is(err, service.ErrTargetNotFriendable):
			ctx.JSON(http.StatusForbidden, gin.H{"message": "Пользователь должен быть другом администратора"})
		default:
			log.Printf("add members error: %v", err)
			ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		}
		return
	}

	for _, uid := range req.UserIDs {
		notif, err := dto.NewNotification("member_added", dto.MemberChangedPayload{
			ChatID: chatID,
			UserID: uid,
			Reason: "added",
		})
		if err == nil {
			h.broadcastJSON(chatID, notif)
		}
	}

	ctx.JSON(http.StatusOK, gin.H{"message": "Участники добавлены"})
}

// KickMember удаляет участника из группы (только admin).
// DELETE /groups/:id/members/:uid
func (h *ChatHandler) KickMember(ctx *gin.Context) {
	myID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}
	chatID, err := parseChatID(ctx)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный ID чата"})
		return
	}
	targetID, err := parseUintParam(ctx, "uid")
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный ID пользователя"})
		return
	}

	if err := h.service.KickMember(chatID, myID, targetID); err != nil {
		switch {
		case errors.Is(err, service.ErrNotAdmin):
			ctx.JSON(http.StatusForbidden, gin.H{"message": "Только администратор может удалять участников"})
		case errors.Is(err, service.ErrNotMember):
			ctx.JSON(http.StatusNotFound, gin.H{"message": "Пользователь не является участником"})
		default:
			log.Printf("kick member error: %v", err)
			ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		}
		return
	}

	notif, err := dto.NewNotification("member_removed", dto.MemberChangedPayload{
		ChatID: chatID,
		UserID: targetID,
		Reason: "kicked",
	})
	if err == nil {
		h.broadcastJSON(chatID, notif)
		h.appHub.NotifyUser(targetID, notif)
	}

	ctx.JSON(http.StatusOK, gin.H{"message": "Участник удалён"})
}

// LeaveGroup выходит из группы.
// DELETE /groups/:id/leave
func (h *ChatHandler) LeaveGroup(ctx *gin.Context) {
	myID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}
	chatID, err := parseChatID(ctx)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный ID чата"})
		return
	}

	membersBefore, _ := h.service.GetGroupMemberIDs(chatID)

	dissolved, err := h.service.LeaveGroup(chatID, myID)
	if err != nil {
		if errors.Is(err, service.ErrNotMember) {
			ctx.JSON(http.StatusForbidden, gin.H{"message": "Вы не участник этой группы"})
			return
		}
		log.Printf("leave group error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	if dissolved {
		dissolveNotif, err := dto.NewNotification("group_dissolved", dto.GroupDissolvedPayload{ChatID: chatID})
		if err == nil {
			for _, mid := range membersBefore {
				h.appHub.NotifyUser(mid, dissolveNotif)
			}
		}
	} else {
		notif, err := dto.NewNotification("member_removed", dto.MemberChangedPayload{
			ChatID: chatID,
			UserID: myID,
			Reason: "left",
		})
		if err == nil {
			h.broadcastJSON(chatID, notif)
		}
	}

	ctx.JSON(http.StatusOK, gin.H{"message": "Вы покинули группу"})
}

// DeleteGroup удаляет группу (только admin).
// DELETE /groups/:id
func (h *ChatHandler) DeleteGroup(ctx *gin.Context) {
	myID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}
	chatID, err := parseChatID(ctx)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный ID чата"})
		return
	}

	membersBefore, _ := h.service.GetGroupMemberIDs(chatID)

	if err := h.service.DeleteGroup(chatID, myID); err != nil {
		if errors.Is(err, service.ErrNotAdmin) {
			ctx.JSON(http.StatusForbidden, gin.H{"message": "Только администратор может удалить группу"})
			return
		}
		log.Printf("delete group error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	notif, err := dto.NewNotification("group_dissolved", dto.GroupDissolvedPayload{ChatID: chatID})
	if err == nil {
		for _, mid := range membersBefore {
			h.appHub.NotifyUser(mid, notif)
		}
	}

	ctx.JSON(http.StatusOK, gin.H{"message": "Группа удалена"})
}

// UpdateGroup обновляет название/аватар группы (только admin).
// PATCH /groups/:id
func (h *ChatHandler) UpdateGroup(ctx *gin.Context) {
	myID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}
	chatID, err := parseChatID(ctx)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный ID чата"})
		return
	}

	var req dto.UpdateGroupRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	chatDTO, err := h.service.UpdateGroup(chatID, myID, req)
	if err != nil {
		if errors.Is(err, service.ErrNotAdmin) {
			ctx.JSON(http.StatusForbidden, gin.H{"message": "Только администратор может изменять группу"})
			return
		}
		log.Printf("update group error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	payload := dto.GroupUpdatedPayload{ChatID: chatID}
	if req.Name != nil {
		payload.Name = *req.Name
	}
	if req.Avatar != nil {
		payload.Avatar = *req.Avatar
	}
	notif, err := dto.NewNotification("group_updated", payload)
	if err == nil {
		h.broadcastJSON(chatID, notif)
	}

	ctx.JSON(http.StatusOK, chatDTO)
}

// SetMemberRole меняет роль участника (только admin).
// PATCH /groups/:id/members/:uid/role
func (h *ChatHandler) SetMemberRole(ctx *gin.Context) {
	myID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}
	chatID, err := parseChatID(ctx)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный ID чата"})
		return
	}
	targetID, err := parseUintParam(ctx, "uid")
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный ID пользователя"})
		return
	}

	var body struct {
		Role string `json:"role" binding:"required"`
	}
	if err := ctx.ShouldBindJSON(&body); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	if err := h.service.SetMemberRole(chatID, myID, targetID, body.Role); err != nil {
		switch {
		case errors.Is(err, service.ErrNotAdmin):
			ctx.JSON(http.StatusForbidden, gin.H{"message": "Только администратор может менять роли"})
		case errors.Is(err, service.ErrNotMember):
			ctx.JSON(http.StatusNotFound, gin.H{"message": "Пользователь не является участником"})
		default:
			log.Printf("set role error: %v", err)
			ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		}
		return
	}

	notif, err := dto.NewNotification("role_changed", dto.RoleChangedPayload{
		ChatID:  chatID,
		UserID:  targetID,
		NewRole: body.Role,
	})
	if err == nil {
		h.broadcastJSON(chatID, notif)
	}

	ctx.JSON(http.StatusOK, gin.H{"message": "Роль изменена"})
}

// PinMessage закрепляет сообщение в чате.
// PATCH /chat/:id/pin
func (h *ChatHandler) PinMessage(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	chatID, err := parseUintParam(ctx, "id")
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный chat_id"})
		return
	}

	var req dto.PinMessageRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Укажите message_id"})
		return
	}

	if err := h.service.PinMessage(chatID, userID, req.MessageID); err != nil {
		log.Printf("pin message error: %v", err)
		ctx.JSON(http.StatusForbidden, gin.H{"message": err.Error()})
		return
	}

	pinned, _ := h.service.GetPinnedMessage(chatID)
	if n, err := dto.NewNotification("message_pinned", dto.MessagePinnedPayload{
		ChatID: chatID,
		Pinned: pinned,
	}); err == nil {
		h.broadcastJSON(chatID, n)
	}

	ctx.JSON(http.StatusOK, gin.H{"pinned": pinned})
}

// UnpinMessage убирает закреплённое сообщение.
// DELETE /chat/:id/pin
func (h *ChatHandler) UnpinMessage(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	chatID, err := parseUintParam(ctx, "id")
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный chat_id"})
		return
	}

	if err := h.service.UnpinMessage(chatID, userID); err != nil {
		log.Printf("unpin message error: %v", err)
		ctx.JSON(http.StatusForbidden, gin.H{"message": err.Error()})
		return
	}

	if n, err := dto.NewNotification("message_pinned", dto.MessagePinnedPayload{
		ChatID: chatID,
		Pinned: nil,
	}); err == nil {
		h.broadcastJSON(chatID, n)
	}

	ctx.Status(http.StatusNoContent)
}

// parseUintParam извлекает именованный параметр пути как uint.
func parseUintParam(ctx *gin.Context, name string) (uint, error) {
	v, err := strconv.ParseUint(ctx.Param(name), 10, 64)
	if err != nil {
		return 0, err
	}
	return uint(v), nil
}
