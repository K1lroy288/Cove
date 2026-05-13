package service

import (
	"cove/internal/model"
	"cove/internal/repository"
	"fmt"
)

type MessageService struct {
	repo *repository.MessageRepository
}

func NewMessageService(repo *repository.MessageRepository) *MessageService {
	return &MessageService{repo: repo}
}

func (s *MessageService) GetMessages(chatID uint, beforeID *uint, limit int) ([]model.Message, error) {
	return s.repo.GetMessages(chatID, beforeID, limit)
}

func (s *MessageService) SendMessage(chatID, senderID uint, content, msgType string) (model.Message, error) {
	if msgType == "" {
		msgType = "text"
	}
	msg, err := s.repo.SaveMessage(chatID, senderID, content, msgType)
	if err != nil {
		return model.Message{}, fmt.Errorf("save message: %w", err)
	}
	return msg, nil
}

func (s *MessageService) IsChatMember(chatID, userID uint) (bool, error) {
	return s.repo.IsChatMember(chatID, userID)
}
