package service

import "cove/internal/repository"

type FriendshipService struct {
	repo *repository.FriendshipRepository
}

func NewFriendshipService(repo *repository.FriendshipRepository) *FriendshipService {
	return &FriendshipService{repo: repo}
}
