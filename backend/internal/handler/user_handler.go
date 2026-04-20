package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/service"
	"cove/internal/utils"
	"errors"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgconn"
	"golang.org/x/crypto/bcrypt"
)

type UserHandler struct {
	service *service.UserService
}

func NewUserHandler(s *service.UserService) *UserHandler {
	return &UserHandler{service: s}
}

func (h *UserHandler) Login(ctx *gin.Context) {
	var req dto.User
	if err := ctx.ShouldBindJSON(&req); err != nil {
		log.Printf("Invalid JSON at login request: %v", err)
		ctx.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON"})
		return
	}

	user, err := h.service.GetUserByUsername(req.Username)
	if err != nil {
		log.Printf("Invalid username or password: %v", err)
		ctx.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid username or password"})
		return
	}

	if err := bcrypt.CompareHashAndPassword(user.PasswordHash, []byte(req.Password)); err != nil {
		log.Printf("Invalid username or password: %v", err)
		ctx.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid username or password"})
		return
	}

	token, err := utils.GenerateJWT(user)
	if err != nil {
		log.Printf("JWT generation failed: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"error": "Authentication failed"})
		return
	}

	response := map[string]string{"token": token}
	ctx.JSON(http.StatusOK, response)
}

func (h *UserHandler) CreateUser(ctx *gin.Context) {
	var req dto.User
	if err := ctx.ShouldBindJSON(&req); err != nil {
		log.Printf("Invalid JSON at register request: %v", err)
		ctx.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON at register request"})
		return
	}

	err := h.service.CreateUser(req)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			log.Printf("Duplicate username: %v", err)
			ctx.JSON(http.StatusBadRequest, gin.H{"error": "Username already exists"})
			return
		}

		log.Printf("create user error: %v", err)
		ctx.Status(http.StatusInternalServerError)
		return
	}

	ctx.Status(http.StatusCreated)
}
