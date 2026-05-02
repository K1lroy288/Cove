package repository

import (
	dto "cove/internal/DTO"
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

func (r *FriendshipRepository) GetPendingRequestsCount(userID uint) (int64, error) {
	var count int64
	err := r.DB.Model(&model.Friendship{}).
		Where("friend_id = ? AND status = ?", userID, model.StatusPending).
		Count(&count).Error
	return count, err
}

func (r *FriendshipRepository) GetPendingRequests(userID uint) ([]dto.FriendRequest, error) {
	var requests []dto.FriendRequest
	err := r.DB.Table("friendships").
		Select("users.id as user_id, users.username").
		Joins("JOIN users ON users.id = friendships.user_id").
		Where("friendships.friend_id = ? AND friendships.status = ?", userID, model.StatusPending).
		Where("users.deleted_at IS NULL").
		Scan(&requests).Error
	return requests, err
}
