package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/service"
	"errors"
	"log"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgconn"
)


type FriendshipHandler struct {
	service *service.FriendshipService
	appHub  *AppHub
}

func NewFriendshipHandler(s *service.FriendshipService, appHub *AppHub) *FriendshipHandler {
	return &FriendshipHandler{service: s, appHub: appHub}
}

// currentUserID извлекает user_id из контекста (установлен JWT middleware).
func currentUserID(ctx *gin.Context) (uint, bool) {
	val, exists := ctx.Get("user_id")
	if !exists {
		return 0, false
	}
	id, ok := val.(uint)
	return id, ok
}

// GetPendingRequests возвращает входящие заявки в друзья для текущего пользователя.
// GET /friendship/pending
func (h *FriendshipHandler) GetPendingRequests(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	requests, err := h.service.GetPendingRequests(userID)
	if err != nil {
		log.Printf("get pending requests error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	ctx.JSON(http.StatusOK, requests)
}

// GetPendingRequestsCount возвращает количество входящих заявок.
// GET /friendship/pending/count
func (h *FriendshipHandler) GetPendingRequestsCount(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	count, err := h.service.GetPendingRequestsCount(userID)
	if err != nil {
		log.Printf("get pending requests count error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	ctx.JSON(http.StatusOK, gin.H{"count": count})
}

// CreateFriendship отправляет заявку в друзья.
// POST /friendship/
// user_id берётся из JWT; friend_id — из тела запроса.
func (h *FriendshipHandler) CreateFriendship(ctx *gin.Context) {
	senderID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	var req dto.Friendship
	if err := ctx.ShouldBindJSON(&req); err != nil {
		log.Printf("Invalid JSON at create friendship request: %v", err)
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	// Принудительно ставим отправителя из JWT — тело запроса игнорируется для user_id.
	req.UserID = senderID

	err := h.service.CreateFriendship(req)
	if err != nil {
		if err.Error() == "cannot add yourself as a friend" {
			ctx.JSON(http.StatusBadRequest, gin.H{"message": "Нельзя добавить себя в друзья"})
			return
		}

		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			log.Printf("Duplicate friendship: %v", err)
			ctx.JSON(http.StatusBadRequest, gin.H{"message": "Запрос уже отправлен"})
			return
		}

		log.Printf("create friendship error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	username := ctx.GetString("username")
	if n, err := dto.NewNotification("friend_request", dto.FriendRequestPayload{
		FromUserID: senderID,
		Username:   username,
	}); err == nil {
		h.appHub.NotifyUser(req.FriendID, n)
	}

	ctx.Status(http.StatusCreated)
}

// RespondToFriendRequest принимает или отклоняет входящую заявку.
// PATCH /friendship/:user_id/status
// :user_id — ID того, кто отправил заявку.
func (h *FriendshipHandler) RespondToFriendRequest(ctx *gin.Context) {
	receiverID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	senderIDStr := ctx.Param("user_id")
	senderID, err := strconv.ParseUint(senderIDStr, 10, 32)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат user_id"})
		return
	}

	var req dto.RespondToRequestDTO
	if err := ctx.ShouldBindJSON(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	if req.Status != "accepted" && req.Status != "declined" {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Недопустимый статус. Ожидается accepted или declined"})
		return
	}

	err = h.service.RespondToFriendRequest(uint(senderID), receiverID, req.Status)
	if err != nil {
		if err.Error() == "request not found" {
			ctx.JSON(http.StatusNotFound, gin.H{"message": "Заявка не найдена"})
			return
		}
		log.Printf("respond to friend request error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	if req.Status == "accepted" {
		username := ctx.GetString("username")
		if n, err := dto.NewNotification("friend_accepted", dto.FriendAcceptedPayload{
			ByUserID: receiverID,
			Username: username,
		}); err == nil {
			h.appHub.NotifyUser(uint(senderID), n)
		}
	}

	message := "Заявка принята"
	if req.Status == "declined" {
		message = "Заявка отклонена"
	}
	ctx.JSON(http.StatusOK, gin.H{"message": message})
}

// GetSentRequests возвращает исходящие pending-заявки текущего пользователя.
// GET /friendship/sent
func (h *FriendshipHandler) GetSentRequests(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	sent, err := h.service.GetSentPendingRequests(userID)
	if err != nil {
		log.Printf("get sent requests error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	ctx.JSON(http.StatusOK, sent)
}

// GetFriends возвращает список друзей текущего пользователя.
// GET /friendship/friends
func (h *FriendshipHandler) GetFriends(ctx *gin.Context) {
	userID, ok := currentUserID(ctx)
	if !ok {
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Необходима авторизация"})
		return
	}

	friends, err := h.service.GetFriends(userID)
	if err != nil {
		log.Printf("get friends error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	ctx.JSON(http.StatusOK, friends)
}
