package dto

import (
	"encoding/json"
	"time"
)

type UserSettingsDTO struct {
	Theme       string                 `json:"theme"`
	Locale      string                 `json:"locale"`
	Preferences map[string]interface{} `json:"preferences"`
}

type UpdateUserSettingsRequest struct {
	Theme       *string                `json:"theme,omitempty"`
	Locale      *string                `json:"locale,omitempty"`
	Preferences map[string]interface{} `json:"preferences,omitempty"`
}

type ChatNotifSettingsDTO struct {
	Muted       bool       `json:"muted"`
	MuteUntil   *time.Time `json:"mute_until,omitempty"`
	NotifyLevel int        `json:"notify_level"`
}

type UpdateChatNotifRequest struct {
	Muted       *bool      `json:"muted,omitempty"`
	MuteUntil   *time.Time `json:"mute_until,omitempty"`
	NotifyLevel *int       `json:"notify_level,omitempty"`
}

// PreferencesToJSON сериализует map в json.RawMessage для JSONB.
func PreferencesToJSON(prefs map[string]interface{}) (json.RawMessage, error) {
	if len(prefs) == 0 {
		return json.RawMessage("{}"), nil
	}
	return json.Marshal(prefs)
}
