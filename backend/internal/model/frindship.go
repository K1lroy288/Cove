package model

import (
	"time"
)

type FriendshipStatus string

const (
	StatusPending  FriendshipStatus = "pending"
	StatusAccepted FriendshipStatus = "accepted"
	StatusBlocked  FriendshipStatus = "blocked"
)

type Friendship struct {
	UserID    uint             `gorm:"primaryKey"`
	FriendID  uint             `gorm:"primaryKey"`
	Status    FriendshipStatus `gorm:"type:friendship_status;default:'pending'"`
	CreatedAt time.Time
	UpdatedAt time.Time
}
