package main

import (
	"cove/internal/config"
	migrator "cove/internal/db"
	"cove/internal/handler"
	"cove/internal/middleware"
	"cove/internal/repository"
	"cove/internal/service"
	"fmt"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

const migrationsDir = "migration"

func main() {
	cfg := config.GetConfig()

	dsn := fmt.Sprintf("host=%s user=%s password=%s dbname=%s port=%s sslmode=disable",
		cfg.DB.Host, cfg.DB.User, cfg.DB.Password, cfg.DB.Name, cfg.DB.Port)

	m := migrator.MustGetNewMigrator(migrator.MigrationsFS, migrationsDir)
	if err := m.ApplyMigrationsWithGORM(dsn); err != nil {
		log.Fatalf("Failed to apply migrations: %v", err)
	}

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	userRepo := repository.NewUserRepository(db)
	userService := service.NewUserService(userRepo)
	userHandler := handler.NewUserHandler(userService)

	friendshipRepo := repository.NewFriendshipRepository(db)
	friendshipService := service.NewFriendshipService(friendshipRepo)
	friendshipHandler := handler.NewFriendshipHandler(friendshipService)

	chatRepo := repository.NewChatRepository(db)
	chatService := service.NewChatService(chatRepo)
	chatHandler := handler.NewChatHandler(chatService)

	messageRepo := repository.NewMessageRepository(db)
	messageService := service.NewMessageService(messageRepo)

	hub := handler.NewHub()
	go hub.Run()

	messageHandler := handler.NewMessageHandler(messageService, hub)

	r := gin.Default()

	r.GET("/health", func(ctx *gin.Context) {
		ctx.String(http.StatusOK, "Cove is up!")
	})

	// ── Auth (без токена) ────────────────────────────────────────────────────────
	auth := r.Group("/auth")
	{
		auth.POST("/login", userHandler.Login)
		auth.POST("/register", userHandler.CreateUser)
	}

	// ── Users (без токена) ───────────────────────────────────────────────────────
	// Маршруты зарегистрированы в строгом порядке: /search и /username/:u до /:id,
	// иначе Gin захватит их как path param.
	user := r.Group("/user")
	{
		user.GET("/search", userHandler.SearchUser)
		user.GET("/username/:username", userHandler.FindUserByUsername)
		user.GET("/:id", userHandler.FindUserByID)
	}

	// ── Friendship (требует JWT) ──────────────────────────────────────────────────
	friendship := r.Group("/friendship")
	friendship.Use(middleware.JWTAuth())
	{
		friendship.GET("/pending", friendshipHandler.GetPendingRequests)
		friendship.GET("/pending/count", friendshipHandler.GetPendingRequestsCount)
		friendship.GET("/friends", friendshipHandler.GetFriends)
		friendship.POST("/", friendshipHandler.CreateFriendship)
		friendship.PATCH("/:user_id/status", friendshipHandler.RespondToFriendRequest)
	}

	// ── Chat (требует JWT) ────────────────────────────────────────────────────────
	chat := r.Group("/chat")
	chat.Use(middleware.JWTAuth())
	{
		chat.GET("/", chatHandler.GetChats)
		chat.POST("/", chatHandler.CreateChat)
		chat.GET("/:id/messages", messageHandler.GetMessages)
		chat.POST("/:id/messages", messageHandler.SendMessage)
	}

	// WS без JWT middleware — токен передаётся через query-параметр ?token=
	r.GET("/chat/:id/ws", messageHandler.ServeWS)

	addr := fmt.Sprintf(":%s", cfg.Port)
	r.Run(addr)
}
