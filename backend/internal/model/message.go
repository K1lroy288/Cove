package model

import (
	"time"

	"gorm.io/gorm"
)

type Message struct {
	ID        uint    `gorm:"primaryKey"`
	ChatID    uint    `gorm:"column:chat_id;not null"`
	SenderID  uint    `gorm:"column:sender_id;not null"`
	Content   string  `gorm:"type:text;not null"`
	Type      string  `gorm:"size:20;not null;default:'text'"`
	ReplyToID *uint   `gorm:"column:reply_to_id"`
	FileName  *string `gorm:"column:file_name;size:255"`
	FileSize  *int64  `gorm:"column:file_size"`
	Caption   *string `gorm:"column:caption;type:text"`
	CreatedAt time.Time
	EditedAt  *time.Time     `gorm:"column:edited_at"`
	DeletedAt gorm.DeletedAt `gorm:"index"`
}

// ChatReadCursor хранит последнее прочитанное сообщение пользователя в чате.
// Одна строка на (chat, user) вместо одной строки на каждое сообщение.
type ChatReadCursor struct {
	ChatID                 uint      `gorm:"primaryKey;column:chat_id"`
	UserID                 uint      `gorm:"primaryKey;column:user_id"`
	LastReadMessageID      *uint     `gorm:"column:last_read_message_id"`
	LastDeliveredMessageID *uint     `gorm:"column:last_delivered_message_id"`
	UpdatedAt              time.Time `gorm:"column:updated_at"`
}
