package repository

import (
	"cove/internal/model"
	"encoding/json"
	"fmt"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type SettingsRepository struct {
	DB *gorm.DB
}

func NewSettingsRepository(db *gorm.DB) *SettingsRepository {
	return &SettingsRepository{DB: db}
}

// GetUserSettings возвращает настройки пользователя, создавая строку дефолтом если её нет.
func (r *SettingsRepository) GetUserSettings(userID uint) (*model.UserSettings, error) {
	s := &model.UserSettings{
		UserID: userID,
		Theme:  "dark",
		Locale: "ru",
	}
	// INSERT ... ON CONFLICT DO NOTHING, затем SELECT
	r.DB.Clauses(clause.OnConflict{DoNothing: true}).Create(s)

	var result model.UserSettings
	if err := r.DB.First(&result, "user_id = ?", userID).Error; err != nil {
		return nil, err
	}
	return &result, nil
}

// UpdateUserSettings обновляет theme/locale и мёржит preferences JSONB.
func (r *SettingsRepository) UpdateUserSettings(userID uint, theme, locale *string, prefs map[string]interface{}) error {
	// Гарантируем наличие строки
	if _, err := r.GetUserSettings(userID); err != nil {
		return err
	}

	updates := map[string]interface{}{
		"updated_at": time.Now(),
	}
	if theme != nil {
		updates["theme"] = *theme
	}
	if locale != nil {
		updates["locale"] = *locale
	}

	if len(prefs) > 0 {
		raw, err := json.Marshal(prefs)
		if err != nil {
			return fmt.Errorf("marshal preferences: %w", err)
		}
		// Мёрж через PostgreSQL JSONB оператор ||
		if err := r.DB.Exec(
			"UPDATE user_settings SET preferences = preferences || ?::jsonb, updated_at = NOW() WHERE user_id = ?",
			string(raw), userID,
		).Error; err != nil {
			return err
		}
		delete(updates, "updated_at")
	}

	if len(updates) > 1 { // больше чем просто updated_at
		return r.DB.Model(&model.UserSettings{}).
			Where("user_id = ?", userID).
			Updates(updates).Error
	}
	return nil
}

// GetChatNotifSettings возвращает настройки уведомлений для чата.
func (r *SettingsRepository) GetChatNotifSettings(userID, chatID uint) (*model.ChatNotificationSettings, error) {
	var s model.ChatNotificationSettings
	err := r.DB.Where("user_id = ? AND chat_id = ?", userID, chatID).First(&s).Error
	if err == gorm.ErrRecordNotFound {
		// Возвращаем дефолт без сохранения в БД
		return &model.ChatNotificationSettings{
			UserID:      userID,
			ChatID:      chatID,
			Muted:       false,
			NotifyLevel: 0,
		}, nil
	}
	return &s, err
}

// UpsertChatNotifSettings создаёт или обновляет настройки уведомлений для чата.
func (r *SettingsRepository) UpsertChatNotifSettings(s *model.ChatNotificationSettings) error {
	return r.DB.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "user_id"}, {Name: "chat_id"}},
		DoUpdates: clause.AssignmentColumns([]string{"muted", "mute_until", "notify_level"}),
	}).Create(s).Error
}
