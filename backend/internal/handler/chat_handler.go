package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/service"
	"errors"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

type ChatHandler struct {
	service *service.ChatService
}

func NewChatHandler(s *service.ChatService) *ChatHandler {
	return &ChatHandler{service: s}
}

// GetChats возвращает список чатов текущего пользователя.
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
