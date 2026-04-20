package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/service"
	"cove/internal/utils"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	service *service.UserService
}

func NewAuthHandler(s *service.UserService) *AuthHandler {
	return &AuthHandler{service: s}
}

func (h *AuthHandler) Login(ctx *gin.Context) {
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
