package dto

import "time"

type ChatDTO struct {
	ID            uint       `json:"id"`
	PartnerID     uint       `json:"partner_id"`
	PartnerName   string     `json:"partner_name"`
	LastMessage   *string    `json:"last_message"`
	LastMessageAt *time.Time `json:"last_message_at"`
	UnreadCount   int        `json:"unread_count"`
}

type CreateChatRequest struct {
	FriendID uint `json:"friend_id" binding:"required"`
}
