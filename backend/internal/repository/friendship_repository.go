package repository

import (
	dto "cove/internal/DTO"
	"cove/internal/model"
	"errors"

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

// RespondToFriendRequest принимает или отклоняет входящую заявку.
// senderID — тот, кто отправил заявку (user_id в таблице friendships).
// receiverID — текущий пользователь (friend_id в таблице friendships).
func (r *FriendshipRepository) RespondToFriendRequest(senderID, receiverID uint, status string) error {
	if status == "accepted" {
		result := r.DB.Model(&model.Friendship{}).
			Where("user_id = ? AND friend_id = ? AND status = ?", senderID, receiverID, model.StatusPending).
			Update("status", model.StatusAccepted)
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected == 0 {
			return errors.New("request not found")
		}
		return nil
	}

	// declined → удалить запись
	result := r.DB.
		Where("user_id = ? AND friend_id = ? AND status = ?", senderID, receiverID, model.StatusPending).
		Delete(&model.Friendship{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return errors.New("request not found")
	}
	return nil
}

// GetFriends возвращает список друзей пользователя (status = accepted, оба направления).
func (r *FriendshipRepository) GetFriends(userID uint) ([]dto.Friend, error) {
	var friends []dto.Friend

	subQuery := r.DB.Raw(
		`SELECT CASE WHEN user_id = ? THEN friend_id ELSE user_id END
		 FROM friendships
		 WHERE (user_id = ? OR friend_id = ?) AND status = ?`,
		userID, userID, userID, model.StatusAccepted,
	)

	err := r.DB.Table("users").
		Select("id, username").
		Where("id IN (?) AND deleted_at IS NULL", subQuery).
		Scan(&friends).Error
	return friends, err
}
