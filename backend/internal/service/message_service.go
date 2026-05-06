package service

import (
	"cove/internal/model"
	"cove/internal/repository"
)

type MessageService struct {
	repo *repository.MessageRepository
}

func NewMessageService(repo *repository.MessageRepository) *MessageService {
	return &MessageService{repo: repo}
}

func (s *MessageService) GetMessages(chatID uint, beforeID *uint, limit int) ([]model.Message, error) {
	return nil, nil
}
