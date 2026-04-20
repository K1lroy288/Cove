package main

import (
	"cove/internal/config"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.GetConfig()

	r := gin.Default()

	r.GET("/health", func(ctx *gin.Context) {
		ctx.String(http.StatusOK, "Cove is up!")
	})

	auth := r.Group("/auth")
	{
		auth.GET("/login")
	}

	addr := fmt.Sprintf(":%s", cfg.AppPort)
	r.Run(addr)
}
