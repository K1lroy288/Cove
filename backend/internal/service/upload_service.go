package service

import (
	"context"
	"encoding/json"
	dto "cove/internal/DTO"
	"cove/internal/config"
	"fmt"
	"mime/multipart"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

const maxUploadSize = 100 << 20 // 100 MB

var imageExtensions = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true,
	".gif": true, ".webp": true, ".bmp": true,
}

var videoExtensions = map[string]bool{
	".mp4": true, ".mov": true, ".webm": true,
	".avi": true, ".mkv": true, ".m4v": true,
}

var audioExtensions = map[string]bool{
	".m4a": true, ".mp3": true, ".wav": true,
	".ogg": true, ".opus": true, ".aac": true,
}

type UploadService struct {
	client    *minio.Client
	bucket    string
	publicURL string
}

func NewUploadService(cfg *config.Config) (*UploadService, error) {
	client, err := minio.New(cfg.MinIO.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.MinIO.AccessKey, cfg.MinIO.SecretKey, ""),
		Secure: cfg.MinIO.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("minio client: %w", err)
	}

	ctx := context.Background()
	exists, err := client.BucketExists(ctx, cfg.MinIO.Bucket)
	if err != nil {
		return nil, fmt.Errorf("bucket exists check: %w", err)
	}
	if !exists {
		if err := client.MakeBucket(ctx, cfg.MinIO.Bucket, minio.MakeBucketOptions{}); err != nil {
			return nil, fmt.Errorf("make bucket: %w", err)
		}
		// Публичная политика на чтение для всего бакета
		policy := buildPublicReadPolicy(cfg.MinIO.Bucket)
		if raw, err := json.Marshal(policy); err == nil {
			_ = client.SetBucketPolicy(ctx, cfg.MinIO.Bucket, string(raw))
		}
	}

	return &UploadService{
		client:    client,
		bucket:    cfg.MinIO.Bucket,
		publicURL: cfg.MinIO.PublicURL,
	}, nil
}

func (s *UploadService) Upload(ctx context.Context, file multipart.File, header *multipart.FileHeader) (dto.UploadResponse, error) {
	if header.Size > maxUploadSize {
		return dto.UploadResponse{}, fmt.Errorf("file too large: %d bytes (max %d)", header.Size, maxUploadSize)
	}

	ext := strings.ToLower(filepath.Ext(header.Filename))
	isImage := imageExtensions[ext]
	isVideo := videoExtensions[ext]
	isAudio := audioExtensions[ext]

	msgType, prefix := "file", "files"
	if isImage {
		msgType, prefix = "image", "images"
	} else if isVideo {
		msgType, prefix = "video", "videos"
	} else if isAudio {
		msgType, prefix = "audio", "audio"
	}

	contentType := header.Header.Get("Content-Type")
	if contentType == "" || contentType == "application/octet-stream" {
		if isImage {
			contentType = "image/jpeg"
		} else if isAudio {
			contentType = "audio/mp4"
		} else {
			contentType = "application/octet-stream"
		}
	}

	month := time.Now().Format("2006/01")
	objectName := fmt.Sprintf("%s/%s/%s%s", prefix, month, uuid.New().String(), ext)

	_, err := s.client.PutObject(ctx, s.bucket, objectName, file, header.Size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	if err != nil {
		return dto.UploadResponse{}, fmt.Errorf("put object: %w", err)
	}

	url := fmt.Sprintf("%s/%s/%s", s.publicURL, s.bucket, objectName)
	return dto.UploadResponse{
		URL:      url,
		Type:     msgType,
		FileName: header.Filename,
		FileSize: header.Size,
	}, nil
}

// buildPublicReadPolicy возвращает S3 bucket policy для публичного чтения.
func buildPublicReadPolicy(bucket string) map[string]any {
	return map[string]any{
		"Version": "2012-10-17",
		"Statement": []map[string]any{
			{
				"Effect":    "Allow",
				"Principal": "*",
				"Action":    []string{"s3:GetObject"},
				"Resource":  []string{fmt.Sprintf("arn:aws:s3:::%s/*", bucket)},
			},
		},
	}
}
