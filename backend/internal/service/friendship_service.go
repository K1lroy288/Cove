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
