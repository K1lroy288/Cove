package service

import (
	dto "cove/internal/DTO"
	"cove/internal/model"
	"cove/internal/repository"
	"encoding/json"
	"fmt"
)

type SettingsService struct {
	repo *repository.SettingsRepository
}

func NewSettingsService(repo *repository.SettingsRepository) *SettingsService {
	return &SettingsService{repo: repo}
}

func (s *SettingsService) GetUserSettings(userID uint) (*dto.UserSettingsDTO, error) {
	m, err := s.repo.GetUserSettings(userID)
	if err != nil {
		return nil, fmt.Errorf("get user settings: %w", err)
	}
	return modelToDTO(m)
}

func (s *SettingsService) UpdateUserSettings(userID uint, req dto.UpdateUserSettingsRequest) (*dto.UserSettingsDTO, error) {
	if err := s.repo.UpdateUserSettings(userID, req.Theme, req.Locale, req.Preferences); err != nil {
		return nil, fmt.Errorf("update user settings: %w", err)
	}
	return s.GetUserSettings(userID)
}

func (s *SettingsService) GetChatNotifSettings(userID, chatID uint) (*dto.ChatNotifSettingsDTO, error) {
	m, err := s.repo.GetChatNotifSettings(userID, chatID)
	if err != nil {
		return nil, fmt.Errorf("get chat notif settings: %w", err)
	}
	return chatNotifToDTO(m), nil
}

func (s *SettingsService) UpdateChatNotifSettings(userID, chatID uint, req dto.UpdateChatNotifRequest) (*dto.ChatNotifSettingsDTO, error) {
	existing, err := s.repo.GetChatNotifSettings(userID, chatID)
	if err != nil {
		return nil, err
	}

	if req.Muted != nil {
		existing.Muted = *req.Muted
	}
	if req.MuteUntil != nil {
		existing.MuteUntil = req.MuteUntil
	}
	if req.NotifyLevel != nil {
		existing.NotifyLevel = int16(*req.NotifyLevel)
	}

	if err := s.repo.UpsertChatNotifSettings(existing); err != nil {
		return nil, fmt.Errorf("upsert chat notif settings: %w", err)
	}
	return chatNotifToDTO(existing), nil
}

func modelToDTO(m *model.UserSettings) (*dto.UserSettingsDTO, error) {
	var prefs map[string]interface{}
	if len(m.Preferences) > 0 {
		if err := json.Unmarshal(m.Preferences, &prefs); err != nil {
			return nil, fmt.Errorf("unmarshal preferences: %w", err)
		}
	}
	if prefs == nil {
		prefs = map[string]interface{}{}
	}
	return &dto.UserSettingsDTO{
		Theme:       m.Theme,
		Locale:      m.Locale,
		Preferences: prefs,
	}, nil
}

func chatNotifToDTO(m *model.ChatNotificationSettings) *dto.ChatNotifSettingsDTO {
	return &dto.ChatNotifSettingsDTO{
		Muted:       m.Muted,
		MuteUntil:   m.MuteUntil,
		NotifyLevel: int(m.NotifyLevel),
	}
}
