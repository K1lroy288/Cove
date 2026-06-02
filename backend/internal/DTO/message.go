package dto

import (
	"cove/internal/model"
	"time"
)

type SendMessageRequest struct {
	Content               string  `json:"content"                binding:"required,max=10000"`
	Type                  string  `json:"type"                   binding:"omitempty,oneof=text image video audio file"`
	FileName              *string `json:"file_name"              binding:"omitempty,max=255"`
	FileSize              *int64  `json:"file_size"`
	Caption               *string `json:"caption"                binding:"omitempty,max=5000"`
	ReplyToID             *uint   `json:"reply_to_id"`
	ForwardedFromID       *uint   `json:"forwarded_from_id"`
	ForwardedFromUsername *string `json:"forwarded_from_username" binding:"omitempty,max=32"`
}

// RepliedMessageDTO — краткая инфо о сообщении, на которое отвечают.
type RepliedMessageDTO struct {
	ID             uint    `json:"id"`
	SenderID       uint    `json:"sender_id"`
	SenderUsername string  `json:"sender_username"`
	Content        string  `json:"content"`
	Type           string  `json:"type"`
}

// ReactionGroupDTO — группа реакций одного эмодзи на сообщение.
type ReactionGroupDTO struct {
	Emoji   string `json:"emoji"`
	Count   int    `json:"count"`
	HasMine bool   `json:"has_mine"`
}

type MessageDTO struct {
	ID                    uint               `json:"id"`
	ChatID                uint               `json:"chat_id"`
	SenderID              uint               `json:"sender_id"`
	Content               string             `json:"content"`
	Type                  string             `json:"type"`
	FileName              *string            `json:"file_name,omitempty"`
	FileSize              *int64             `json:"file_size,omitempty"`
	Caption               *string            `json:"caption,omitempty"`
	ReplyTo               *RepliedMessageDTO `json:"reply_to,omitempty"`
	ForwardedFromID       *uint              `json:"forwarded_from_id,omitempty"`
	ForwardedFromUsername *string            `json:"forwarded_from_username,omitempty"`
	EditedAt              *time.Time         `json:"edited_at,omitempty"`
	IsDeleted             bool               `json:"is_deleted"`
	Reactions             []ReactionGroupDTO `json:"reactions,omitempty"`
	CreatedAt             time.Time          `json:"created_at"`
}

// EditMessageRequest — тело PATCH /chat/:id/messages/:msg_id.
type EditMessageRequest struct {
	Content string `json:"content" binding:"required,min=1,max=10000"`
}

// PinMessageRequest — тело PATCH /chat/:id/pin.
type PinMessageRequest struct {
	MessageID uint `json:"message_id" binding:"required"`
}

// PinnedMessageDTO — вложенный объект в ChatDTO.
type PinnedMessageDTO struct {
	ID       uint   `json:"id"`
	SenderID uint   `json:"sender_id"`
	Content  string `json:"content"`
	Type     string `json:"type"`
}

func ToMessageDTO(m model.Message) MessageDTO {
	return MessageDTO{
		ID:                    m.ID,
		ChatID:                m.ChatID,
		SenderID:              m.SenderID,
		Content:               m.Content,
		Type:                  m.Type,
		FileName:              m.FileName,
		FileSize:              m.FileSize,
		Caption:               m.Caption,
		ForwardedFromID:       m.ForwardedFromID,
		ForwardedFromUsername: m.ForwardedFromUsername,
		EditedAt:              m.EditedAt,
		IsDeleted:             m.DeletedAt.Valid,
		CreatedAt:             m.CreatedAt,
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
