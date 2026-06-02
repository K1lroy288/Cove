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
	friendshipRepo := repository.NewFriendshipRepository(db)
	userService := service.NewUserService(userRepo, friendshipRepo)
	userHandler := handler.NewUserHandler(userService)

	messageRepo := repository.NewMessageRepository(db)
	messageService := service.NewMessageService(messageRepo)

	friendshipService := service.NewFriendshipService(friendshipRepo)

	appHub := handler.NewAppHub(
		messageService.IsChatMember,
		messageService.MarkDelivered,
		messageService.MarkRead,
		friendshipService.GetFriendIDs,
		friendshipService.UpdateLastSeen,
	)
	go appHub.Run()

	friendshipHandler := handler.NewFriendshipHandler(friendshipService, appHub)

	chatRepo := repository.NewChatRepository(db)
	chatService := service.NewChatService(chatRepo)
	chatHandler := handler.NewChatHandler(chatService, appHub)

	messageHandler := handler.NewMessageHandler(messageService, appHub)

	settingsRepo := repository.NewSettingsRepository(db)
	settingsService := service.NewSettingsService(settingsRepo)
	settingsHandler := handler.NewSettingsHandler(settingsService)

	uploadService, err := service.NewUploadService(cfg)
	if err != nil {
		log.Fatalf("Failed to init upload service: %v", err)
	}
	uploadHandler := handler.NewUploadHandler(uploadService)

	// Rate limiters
	authLimiter := middleware.NewRateLimiter(10.0/60, 15)    // 10 req/min per IP, burst 15
	searchLimiter := middleware.NewRateLimiter(30.0/60, 10)  // 30 req/min per IP
	msgLimiter := middleware.NewUserRateLimiter(60.0/60, 20) // 60 msg/min per user, burst 20

	r := gin.Default()

	r.GET("/health", func(ctx *gin.Context) {
		ctx.String(http.StatusOK, "Cove is up!")
	})

	// ── Auth (без токена) ────────────────────────────────────────────────────────
	auth := r.Group("/auth")
	auth.Use(authLimiter.Middleware())
	{
		auth.POST("/login", userHandler.Login)
		auth.POST("/register", userHandler.CreateUser)
	}

	// ── Users (без токена) ───────────────────────────────────────────────────────
	user := r.Group("/user")
	{
		user.GET("/search", searchLimiter.Middleware(), userHandler.SearchUser)
		user.GET("/username/:username", userHandler.FindUserByUsername)
		user.GET("/:id", userHandler.FindUserByID)
	}

	// ── User profile (требует JWT) ───────────────────────────────────────────────
	userAuth := r.Group("/user")
	userAuth.Use(middleware.JWTAuth())
	{
		userAuth.GET("/presence", handler.GetPresence(appHub))
		userAuth.GET("/me", userHandler.GetMe)
		userAuth.PATCH("/me", userHandler.UpdateMe)
		userAuth.POST("/me/password", userHandler.ChangePassword)
		userAuth.DELETE("/me", userHandler.DeleteMe)
		userAuth.GET("/:id/profile", userHandler.GetUserProfile)
	}

	// ── Friendship (требует JWT) ──────────────────────────────────────────────────
	friendship := r.Group("/friendship")
	friendship.Use(middleware.JWTAuth())
	{
		friendship.GET("/pending", friendshipHandler.GetPendingRequests)
		friendship.GET("/pending/count", friendshipHandler.GetPendingRequestsCount)
		friendship.GET("/sent", friendshipHandler.GetSentRequests)
		friendship.GET("/friends", friendshipHandler.GetFriends)
		friendship.GET("/blocked", friendshipHandler.GetBlockedUsers)
		friendship.POST("/", friendshipHandler.CreateFriendship)
		friendship.PATCH("/:user_id/status", friendshipHandler.RespondToFriendRequest)
		friendship.DELETE("/:user_id", friendshipHandler.RemoveFriend)
		friendship.POST("/:user_id/block", friendshipHandler.BlockUser)
		friendship.DELETE("/:user_id/block", friendshipHandler.UnblockUser)
	}

	// ── Chat (требует JWT) ────────────────────────────────────────────────────────
	chat := r.Group("/chat")
	chat.Use(middleware.JWTAuth())
	{
		chat.GET("/", chatHandler.GetChats)
		chat.POST("/", chatHandler.CreateChat)
		chat.PATCH("/:id/pin", chatHandler.PinMessage)
		chat.DELETE("/:id/pin", chatHandler.UnpinMessage)
		chat.GET("/:id/messages", messageHandler.GetMessages)
		chat.POST("/:id/messages", msgLimiter.Middleware(), messageHandler.SendMessage)
		chat.GET("/:id/messages/search", messageHandler.SearchMessages)
		chat.PATCH("/:id/messages/:msg_id", messageHandler.EditMessage)
		chat.DELETE("/:id/messages/:msg_id", messageHandler.DeleteMessage)
		chat.POST("/:id/messages/:msg_id/reactions", messageHandler.ToggleReaction)
	}

	// ── Groups (требует JWT) ─────────────────────────────────────────────────────
	groups := r.Group("/groups")
	groups.Use(middleware.JWTAuth())
	{
		groups.POST("/", chatHandler.CreateGroup)
		groups.GET("/:id/members", chatHandler.GetGroupMembers)
		groups.POST("/:id/members", chatHandler.AddMembers)
		groups.DELETE("/:id/members/:uid", chatHandler.KickMember)
		groups.DELETE("/:id/leave", chatHandler.LeaveGroup)
		groups.DELETE("/:id", chatHandler.DeleteGroup)
		groups.PATCH("/:id", chatHandler.UpdateGroup)
		groups.PATCH("/:id/members/:uid/role", chatHandler.SetMemberRole)
	}

	// ── Settings (требует JWT) ───────────────────────────────────────────────────
	settings := r.Group("/settings")
	settings.Use(middleware.JWTAuth())
	{
		settings.GET("/", settingsHandler.GetSettings)
		settings.PATCH("/", settingsHandler.UpdateSettings)
		settings.GET("/chat/:id", settingsHandler.GetChatNotifSettings)
		settings.PATCH("/chat/:id", settingsHandler.UpdateChatNotifSettings)
	}

	// ── Upload (требует JWT) ─────────────────────────────────────────────────────
	upload := r.Group("/upload")
	upload.Use(middleware.JWTAuth())
	{
		upload.POST("/", uploadHandler.Upload)
	}

	// WS без JWT middleware — токен передаётся через query-параметр ?token=
	r.GET("/ws", appHub.ServeWS)

	addr := fmt.Sprintf(":%s", cfg.Port)
	r.Run(addr)
}
