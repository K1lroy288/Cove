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

func NewNotification(typeName string, payload any) (NotificationDTO, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return NotificationDTO{}, err
	}
	return NotificationDTO{Type: typeName, Payload: raw}, nil
}
