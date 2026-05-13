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
		return r.DB.Transaction(func(tx *gorm.DB) error {
			// Обновить исходную заявку: (senderID → receiverID) pending → accepted
			result := tx.Model(&model.Friendship{}).
				Where("user_id = ? AND friend_id = ? AND status = ?", senderID, receiverID, model.StatusPending).
				Update("status", model.StatusAccepted)
			if result.Error != nil {
				return result.Error
			}
			if result.RowsAffected == 0 {
				return errors.New("request not found")
			}

			// Создать симметричную запись: (receiverID → senderID) accepted
			// Благодаря этому GetFriends делает простой WHERE user_id=? AND status='accepted'
			reverse := &model.Friendship{
				UserID:   receiverID,
				FriendID: senderID,
				Status:   model.StatusAccepted,
			}
			return tx.Create(reverse).Error
		})
	}

	// declined → удалить заявку
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

// GetSentPendingRequests возвращает пользователей, которым текущий пользователь отправил заявку (статус pending).
func (r *FriendshipRepository) GetSentPendingRequests(userID uint) ([]dto.Friend, error) {
	var friends []dto.Friend
	err := r.DB.Table("friendships").
		Select("users.id, users.username").
		Joins("JOIN users ON users.id = friendships.friend_id").
		Where("friendships.user_id = ? AND friendships.status = ? AND users.deleted_at IS NULL", userID, model.StatusPending).
		Scan(&friends).Error
	return friends, err
}

// GetFriends возвращает список друзей пользователя.
// Работает корректно благодаря симметричным записям: при принятии заявки
// создаются обе строки (A→B и B→A), поэтому достаточно WHERE user_id=?.
func (r *FriendshipRepository) GetFriends(userID uint) ([]dto.Friend, error) {
	var friends []dto.Friend
	err := r.DB.Table("friendships").
		Select("users.id, users.username").
		Joins("JOIN users ON users.id = friendships.friend_id").
		Where("friendships.user_id = ? AND friendships.status = ? AND users.deleted_at IS NULL", userID, model.StatusAccepted).
		Scan(&friends).Error
	return friends, err
}
