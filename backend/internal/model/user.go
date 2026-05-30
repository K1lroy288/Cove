package model

import (
	"time"

	"gorm.io/datatypes"
	"gorm.io/gorm"
)

type User struct {
	gorm.Model
	ID           uint           `gorm:"primary key; not null"`
	Username     string         `gorm:"size:100;not null;unique"`
	PasswordHash []byte         `gorm:"not null"`
	Bio          *string        `gorm:"size:500"`
	AvatarURL    *string        `gorm:"column:avatar_url;size:500"`
	Settings     datatypes.JSON `gorm:"types:jsonb"`
	LastSeenAt   *time.Time     `gorm:"column:last_seen_at"`
	CreatedAt    time.Time
	UpdatedAt    time.Time

	Friends []User `gorm:"many2many:friendships;joinForeignKey:UserID;JoinReferences:FriendID"`
}
