package main

import (
	"cove/internal/config"
	migrator "cove/internal/db"
	"cove/internal/handler"
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

	migrator := migrator.MustGetNewMigrator(migrator.MigrationsFS, migrationsDir)

	err := migrator.ApplyMigrationsWithGORM(dsn)
	if err != nil {
		log.Fatalf("Failed to apply migrations: %v", err)
	}

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	repo := repository.NewUserRepository(db)
	service := service.NewUserService(repo)
	handler := handler.NewUserHandler(service)

	r := gin.Default()

	r.GET("/health", func(ctx *gin.Context) {
		ctx.String(http.StatusOK, "Cove is up!")
	})

	auth := r.Group("/auth")
	{
		auth.GET("/login", handler.Login)
	}

	addr := fmt.Sprintf(":%s", cfg.Port)
	r.Run(addr)
}
