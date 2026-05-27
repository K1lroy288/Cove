package handler

import (
	"cove/internal/service"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

type UploadHandler struct {
	uploadService *service.UploadService
}

func NewUploadHandler(uploadService *service.UploadService) *UploadHandler {
	return &UploadHandler{uploadService: uploadService}
}

// Upload принимает файл через multipart/form-data, сохраняет в MinIO и возвращает URL.
// POST /upload
func (h *UploadHandler) Upload(ctx *gin.Context) {
	if err := ctx.Request.ParseMultipartForm(100 << 20); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Ошибка разбора формы"})
		return
	}

	file, header, err := ctx.Request.FormFile("file")
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"message": "Поле file обязательно"})
		return
	}
	defer file.Close()

	resp, err := h.uploadService.Upload(ctx.Request.Context(), file, header)
	if err != nil {
		log.Printf("upload error: %v", err)
		ctx.JSON(http.StatusInternalServerError, gin.H{"message": "Ошибка загрузки файла"})
		return
	}

	ctx.JSON(http.StatusOK, resp)
}
