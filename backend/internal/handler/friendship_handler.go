package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/service"
	"errors"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgconn"
)

type FriendshipHandler struct {
	service *service.FriendshipService
}

func NewFriendshipHandler(s *service.FriendshipService) *FriendshipHandler {
	return &FriendshipHandler{service: s}
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
