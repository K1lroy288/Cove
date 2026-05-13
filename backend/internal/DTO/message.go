package dto

import (
	"cove/internal/model"
	"time"
)

type SendMessageRequest struct {
	Content string `json:"content" binding:"required"`
	Type    string `json:"type"`
}

type MessageDTO struct {
	ID        uint      `json:"id"`
	ChatID    uint      `json:"chat_id"`
	SenderID  uint      `json:"sender_id"`
	Content   string    `json:"content"`
	Type      string    `json:"type"`
	CreatedAt time.Time `json:"created_at"`
}

func ToMessageDTO(m model.Message) MessageDTO {
	return MessageDTO{
		ID:        m.ID,
		ChatID:    m.ChatID,
		SenderID:  m.SenderID,
		Content:   m.Content,
		Type:      m.Type,
		CreatedAt: m.CreatedAt,
	}
}
