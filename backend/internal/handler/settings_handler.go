package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/service"
	"log"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

type SettingsHandler struct {
	service *service.SettingsService
}

func NewSettingsHandler(s *service.SettingsService) *SettingsHandler {
	return &SettingsHandler{service: s}
}

// GetSettings возвращает настройки текущего пользователя.
// GET /settings
func (h *SettingsHandler) GetSettings(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	result, err := h.service.GetUserSettings(userID)
	if err != nil {
		log.Printf("GetSettings error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка получения настроек"})
		return
	}

	ctx.JSON(http.StatusOK, result)
}

// UpdateSettings обновляет настройки текущего пользователя (partial update).
// PATCH /settings
func (h *SettingsHandler) UpdateSettings(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	var req dto.UpdateUserSettingsRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный запрос"})
		return
	}

	result, err := h.service.UpdateUserSettings(userID, req)
	if err != nil {
		log.Printf("UpdateSettings error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка обновления настроек"})
		return
	}

	ctx.JSON(http.StatusOK, result)
}

// GetChatNotifSettings возвращает настройки уведомлений для чата.
// GET /settings/chat/:id
func (h *SettingsHandler) GetChatNotifSettings(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	chatID, err := strconv.ParseUint(ctx.Param("id"), 10, 64)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный id чата"})
		return
	}

	result, err := h.service.GetChatNotifSettings(userID, uint(chatID))
	if err != nil {
		log.Printf("GetChatNotifSettings error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка получения настроек чата"})
		return
	}

	ctx.JSON(http.StatusOK, result)
}

// UpdateChatNotifSettings обновляет настройки уведомлений для чата.
// PATCH /settings/chat/:id
func (h *SettingsHandler) UpdateChatNotifSettings(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	chatID, err := strconv.ParseUint(ctx.Param("id"), 10, 64)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный id чата"})
		return
	}

	var req dto.UpdateChatNotifRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Некорректный запрос"})
		return
	}

	result, err := h.service.UpdateChatNotifSettings(userID, uint(chatID), req)
	if err != nil {
		log.Printf("UpdateChatNotifSettings error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка обновления настроек чата"})
		return
	}

	ctx.JSON(http.StatusOK, result)
}
