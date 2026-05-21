package dto

import (
	"encoding/json"
	"time"
)

type NotificationDTO struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

type NewMessagePayload struct {
	MessageID uint      `json:"message_id"`
	ChatID    uint      `json:"chat_id"`
	SenderID  uint      `json:"sender_id"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
}

type FriendRequestPayload struct {
	FromUserID uint   `json:"from_user_id"`
	Username   string `json:"username"`
}

type FriendAcceptedPayload struct {
	ByUserID uint   `json:"by_user_id"`
	Username string `json:"username"`
}

type GroupCreatedPayload struct {
	ChatID      uint   `json:"chat_id"`
	GroupName   string `json:"group_name"`
	GroupAvatar string `json:"group_avatar"`
	CreatedBy   uint   `json:"created_by"`
}

type GroupUpdatedPayload struct {
	ChatID uint   `json:"chat_id"`
	Name   string `json:"name"`
	Avatar string `json:"avatar"`
}

// MemberChangedPayload используется для member_added и member_removed.
// Reason: "added" | "kicked" | "left"
type MemberChangedPayload struct {
	ChatID   uint   `json:"chat_id"`
	UserID   uint   `json:"user_id"`
	Username string `json:"username"`
	Reason   string `json:"reason"`
}

type GroupDissolvedPayload struct {
	ChatID uint `json:"chat_id"`
}

type RoleChangedPayload struct {
	ChatID  uint   `json:"chat_id"`
	UserID  uint   `json:"user_id"`
	NewRole string `json:"new_role"`
}

type MessageDeliveredPayload struct {
	ChatID      uint      `json:"chat_id"`
	MessageID   uint      `json:"message_id"`
	DeliveredAt time.Time `json:"delivered_at"`
}

type MessageReadPayload struct {
	ChatID            uint      `json:"chat_id"`
	LastReadMessageID uint      `json:"last_read_message_id"`
	ReadAt            time.Time `json:"read_at"`
}

type UserPresencePayload struct {
	UserID   uint `json:"user_id"`
	IsOnline bool `json:"is_online"`
}

func NewNotification(typeName string, payload any) (NotificationDTO, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return NotificationDTO{}, err
	}
	return NotificationDTO{Type: typeName, Payload: raw}, nil
}
