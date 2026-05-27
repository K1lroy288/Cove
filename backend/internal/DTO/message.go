package dto

import (
	"cove/internal/model"
	"time"
)

type SendMessageRequest struct {
	Content  string  `json:"content" binding:"required"`
	Type     string  `json:"type"`
	FileName *string `json:"file_name"`
	FileSize *int64  `json:"file_size"`
	Caption  *string `json:"caption"`
}

type MessageDTO struct {
	ID        uint      `json:"id"`
	ChatID    uint      `json:"chat_id"`
	SenderID  uint      `json:"sender_id"`
	Content   string    `json:"content"`
	Type      string    `json:"type"`
	FileName  *string   `json:"file_name,omitempty"`
	FileSize  *int64    `json:"file_size,omitempty"`
	Caption   *string   `json:"caption,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

func ToMessageDTO(m model.Message) MessageDTO {
	return MessageDTO{
		ID:        m.ID,
		ChatID:    m.ChatID,
		SenderID:  m.SenderID,
		Content:   m.Content,
		Type:      m.Type,
		FileName:  m.FileName,
		FileSize:  m.FileSize,
		Caption:   m.Caption,
		CreatedAt: m.CreatedAt,
	}
}

// UploadResponse — ответ на POST /upload.
type UploadResponse struct {
	URL      string `json:"url"`
	Type     string `json:"type"`
	FileName string `json:"file_name"`
	FileSize int64  `json:"file_size"`
}

// PartnerCursorDTO — курсоры партнёра в DM для вычисления статуса сообщений на клиенте.
type PartnerCursorDTO struct {
	LastReadMessageID      *uint `json:"last_read_message_id"`
	LastDeliveredMessageID *uint `json:"last_delivered_message_id"`
}

// GetMessagesResponse — ответ на GET /chat/:id/messages.
// PartnerCursor заполняется только для DM; для групп — nil.
type GetMessagesResponse struct {
	Messages      []MessageDTO      `json:"messages"`
	PartnerCursor *PartnerCursorDTO `json:"partner_cursor,omitempty"`
}
