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
}

func NewFriendshipHandler(s *service.FriendshipService) *FriendshipHandler {
	return &FriendshipHandler{service: s}
}

func (h *FriendshipHandler) GetPendingRequests(ctx *gin.Context) {
	userIDStr := ctx.Query("user_id")
	userID, err := strconv.ParseUint(userIDStr, 10, 32)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат user_id"})
		return
	}

	requests, err := h.service.GetPendingRequests(uint(userID))
	if err != nil {
		log.Printf("get pending requests error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	ctx.JSON(http.StatusOK, requests)
}

func (h *FriendshipHandler) GetPendingRequestsCount(ctx *gin.Context) {
	userIDStr := ctx.Query("user_id")
	userID, err := strconv.ParseUint(userIDStr, 10, 32)
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат user_id"})
		return
	}

	count, err := h.service.GetPendingRequestsCount(uint(userID))
	if err != nil {
		log.Printf("get pending requests count error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	ctx.JSON(http.StatusOK, gin.H{"count": count})
}

func (h *FriendshipHandler) CreateFriendship(ctx *gin.Context) {
	var req dto.Friendship
	if err := ctx.ShouldBindJSON(&req); err != nil {
		log.Printf("Invalid JSON at create friendship request: %v", err)
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	err := h.service.CreateFriendship(req)
	if err != nil {
		if err.Error() == "cannot add yourself as a friend" {
			ctx.JSON(http.StatusBadRequest, gin.H{"message": "Нельзя добавить себя в друзья"})
			return
		}

		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			log.Printf("Duplicate friendship: %v", err)
			ctx.JSON(http.StatusBadRequest, gin.H{"message": "Запись о дружбе уже существует"})
			return
		}

		log.Printf("create friendship error: %v", err)
		ctx.Status(http.StatusInternalServerError)
		return
	}

	ctx.Status(http.StatusCreated)
}
