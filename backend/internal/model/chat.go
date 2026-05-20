package model

import (
	"time"
)

type Chat struct {
	ID                 uint       `gorm:"primaryKey"`
	ChatType           string     `gorm:"column:chat_type;default:'dm'"`
	Name               *string    `gorm:"column:name"`
	Avatar             *string    `gorm:"column:avatar"`
	CreatedBy          *uint      `gorm:"column:created_by"`
	LastMessageID      *uint      `gorm:"column:last_message_id"`
	LastMessageAt      *time.Time `gorm:"column:last_message_at"`
	LastMessageContent *string    `gorm:"column:last_message_content"`
	CreatedAt          time.Time
}

type ChatMember struct {
	ChatID   uint      `gorm:"primaryKey;column:chat_id"`
	UserID   uint      `gorm:"primaryKey;column:user_id"`
	Role     string    `gorm:"column:role;default:'member'"`
	JoinedAt time.Time `gorm:"column:joined_at"`
}
