package repository

import (
	"cove/internal/model"

	"gorm.io/gorm"
)

type FriendshipRepository struct {
	DB *gorm.DB
}

func NewFriendshipRepository(db *gorm.DB) *FriendshipRepository {
	return &FriendshipRepository{DB: db}
}

func (r *FriendshipRepository) CreateFriendship(friendship *model.Friendship) error {
	return r.DB.Create(friendship).Error
}
