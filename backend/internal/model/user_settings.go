package model

import (
	"time"

	"gorm.io/datatypes"
)

type UserSettings struct {
	UserID      uint           `gorm:"primaryKey"`
	Theme       string         `gorm:"default:dark"`
	Locale      string         `gorm:"default:ru"`
	Preferences datatypes.JSON `gorm:"default:'{}'"`
	UpdatedAt   time.Time
}

type ChatNotificationSettings struct {
	UserID      uint       `gorm:"primaryKey"`
	ChatID      uint       `gorm:"primaryKey"`
	Muted       bool       `gorm:"default:false"`
	MuteUntil   *time.Time
	NotifyLevel int16      `gorm:"default:0"`
}
