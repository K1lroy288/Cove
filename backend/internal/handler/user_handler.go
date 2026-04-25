package handler

import (
	dto "cove/internal/DTO"
	"cove/internal/service"
	"cove/internal/utils"
	"errors"
	"log"
	"net/http"
	"strconv"

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
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	user, err := h.service.GetUserByUsername(req.Username)
	if err != nil {
		log.Printf("Invalid username or password: %v", err)
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Неверное имя пользователя или пароль"})
		return
	}

	if err := bcrypt.CompareHashAndPassword(user.PasswordHash, []byte(req.Password)); err != nil {
		log.Printf("Invalid username or password: %v", err)
		ctx.JSON(http.StatusUnauthorized, gin.H{"message": "Неверное имя пользователя или пароль"})
		return
	}

	token, err := utils.GenerateJWT(user)
	if err != nil {
		log.Printf("JWT generation failed: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка аутентификации. Попробуйте позже"})
		return
	}

	response := gin.H{
		"token":    token,
		"userId":   "usr_123",
		"username": req.Username,
	}
	ctx.JSON(http.StatusOK, response)
}

func (h *UserHandler) CreateUser(ctx *gin.Context) {
	var req dto.User
	if err := ctx.ShouldBindJSON(&req); err != nil {
		log.Printf("Invalid JSON at register request: %v", err)
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	err := h.service.CreateUser(req)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			log.Printf("Duplicate username: %v", err)
			ctx.JSON(http.StatusBadRequest, gin.H{"message": "Пользователь с таким именем уже существует"})
			return
		}

		log.Printf("create user error: %v", err)
		ctx.Status(http.StatusInternalServerError)
		return
	}

	ctx.Status(http.StatusCreated)
}

func (h *UserHandler) FindUserByID(ctx *gin.Context) {
	id := ctx.Param("id")

	idUint, err := strconv.ParseUint(id, 10, 32)
	if err != nil {
		log.Printf("wrong id format: %v", err)
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Неверный формат данных"})
		return
	}

	user, err := h.service.GetUserByID(uint(idUint))
	if err != nil {
		if err.Error() == "user not found" {
			ctx.JSON(http.StatusNotFound, gin.H{"message": "Пользователь не найден"})
			return
		}

		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка сервера"})
		return
	}

	ctx.JSON(http.StatusOK, user)
}
