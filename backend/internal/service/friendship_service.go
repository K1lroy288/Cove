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

func (s *FriendshipService) GetSentPendingRequests(userID uint) ([]dto.Friend, error) {
	return s.repo.GetSentPendingRequests(userID)
}

func (s *FriendshipService) GetFriends(userID uint) ([]dto.Friend, error) {
	return s.repo.GetFriends(userID)
}

func (s *FriendshipService) GetFriendIDs(userID uint) ([]uint, error) {
	return s.repo.GetFriendIDs(userID)
}

func (s *FriendshipService) RemoveFriend(userID, friendID uint) error {
	return s.repo.RemoveFriend(userID, friendID)
}

func (s *FriendshipService) BlockUser(blockerID, targetID uint) error {
	if blockerID == targetID {
		return errors.New("cannot block yourself")
	}
	return s.repo.BlockUser(blockerID, targetID)
}

func (s *FriendshipService) UnblockUser(blockerID, targetID uint) error {
	return s.repo.UnblockUser(blockerID, targetID)
}

func (s *FriendshipService) GetBlockedUsers(userID uint) ([]dto.Friend, error) {
	return s.repo.GetBlockedUsers(userID)
}

func (s *FriendshipService) UpdateLastSeen(userID uint) error {
	return s.repo.UpdateLastSeen(userID)
}

func (s *FriendshipService) IsBlocked(blockerID, targetID uint) bool {
	return s.repo.IsBlocked(blockerID, targetID)
}
