package service

import (
	dto "cove/internal/DTO"
	"cove/internal/model"
	"cove/internal/repository"
	"errors"
)

type FriendshipService struct {
	repo *repository.FriendshipRepository
}

func NewFriendshipService(repo *repository.FriendshipRepository) *FriendshipService {
	return &FriendshipService{repo: repo}
}

func (s *FriendshipService) GetPendingRequestsCount(userID uint) (int64, error) {
	return s.repo.GetPendingRequestsCount(userID)
}

func (s *FriendshipService) GetPendingRequests(userID uint) ([]dto.FriendRequest, error) {
	return s.repo.GetPendingRequests(userID)
}

func (s *FriendshipService) CreateFriendship(friendshipDTO dto.Friendship) error {
	if friendshipDTO.UserID == friendshipDTO.FriendID {
		return errors.New("cannot add yourself as a friend")
	}

	friendship := &model.Friendship{
		UserID:   friendshipDTO.UserID,
		FriendID: friendshipDTO.FriendID,
		Status:   model.StatusPending,
	}

	return s.repo.CreateFriendship(friendship)
}

func (s *FriendshipService) RespondToFriendRequest(senderID, receiverID uint, status string) error {
	return s.repo.RespondToFriendRequest(senderID, receiverID, status)
}

func (s *FriendshipService) GetFriends(userID uint) ([]dto.Friend, error) {
	return s.repo.GetFriends(userID)
}
