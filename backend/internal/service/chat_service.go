package service

import (
	dto "cove/internal/DTO"
	"cove/internal/repository"
	"errors"
)

var ErrNotFriends = errors.New("not friends")

type ChatService struct {
	repo *repository.ChatRepository
}

func NewChatService(repo *repository.ChatRepository) *ChatService {
	return &ChatService{repo: repo}
}

func (s *ChatService) GetChats(userID uint) ([]dto.ChatDTO, error) {
	return s.repo.GetChats(userID)
}

// CreateOrGetChat возвращает существующий чат или создаёт новый.
// Второй возврат — true если чат только что создан (201), false если уже существовал (200).
func (s *ChatService) CreateOrGetChat(myUserID, friendID uint) (*dto.ChatDTO, bool, error) {
	isFriend, err := s.repo.IsFriend(myUserID, friendID)
	if err != nil {
		return nil, false, err
	}
	if !isFriend {
		return nil, false, ErrNotFriends
	}

	existingID, err := s.repo.FindExistingChat(myUserID, friendID)
	if err != nil {
		return nil, false, err
	}
	if existingID != 0 {
		chat, err := s.repo.GetChatDTO(existingID, myUserID)
		return chat, false, err
	}

	newChat, err := s.repo.CreateChat(myUserID, friendID)
	if err != nil {
		return nil, false, err
	}
	chat, err := s.repo.GetChatDTO(newChat.ID, myUserID)
	return chat, true, err
}
