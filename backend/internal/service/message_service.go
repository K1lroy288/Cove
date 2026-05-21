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

func (s *MessageService) GetPartnerID(chatID, senderID uint) (uint, error) {
	return s.repo.GetPartnerID(chatID, senderID)
}

func (s *MessageService) GetChatMemberIDs(chatID uint) ([]uint, error) {
	return s.repo.GetChatMemberIDs(chatID)
}

func (s *MessageService) IsDMChat(chatID uint) (bool, error) {
	return s.repo.IsDMChat(chatID)
}

// MarkDelivered обновляет курсор доставки и возвращает senderID для уведомления.
func (s *MessageService) MarkDelivered(chatID, userID, messageID uint) (uint, error) {
	if err := s.repo.UpsertDeliveredCursor(chatID, userID, messageID); err != nil {
		return 0, fmt.Errorf("upsert delivered cursor: %w", err)
	}
	return s.repo.GetMessageSenderID(messageID)
}

// MarkRead обновляет курсор прочтения (и доставки) и возвращает senderID для уведомления.
func (s *MessageService) MarkRead(chatID, userID, messageID uint) (uint, error) {
	if err := s.repo.UpsertReadCursor(chatID, userID, messageID); err != nil {
		return 0, fmt.Errorf("upsert read cursor: %w", err)
	}
	return s.repo.GetMessageSenderID(messageID)
}

// GetPartnerCursor возвращает курсор партнёра в DM для отображения статуса сообщений.
func (s *MessageService) GetPartnerCursor(chatID, myUserID uint) (*model.ChatReadCursor, error) {
	return s.repo.GetPartnerCursor(chatID, myUserID)
}
