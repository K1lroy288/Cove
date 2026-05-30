package repository

import (
	dto "cove/internal/DTO"
	"cove/internal/model"
	"errors"
	"time"

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
		Select("users.id as user_id, users.username, users.avatar_url").
		Joins("JOIN users ON users.id = friendships.user_id").
		Where("friendships.friend_id = ? AND friendships.status = ?", userID, model.StatusPending).
		Where("users.deleted_at IS NULL").
		Scan(&requests).Error
	return requests, err
}

// RespondToFriendRequest принимает или отклоняет входящую заявку.
func (r *FriendshipRepository) RespondToFriendRequest(senderID, receiverID uint, status string) error {
	if status == "accepted" {
		return r.DB.Transaction(func(tx *gorm.DB) error {
			result := tx.Model(&model.Friendship{}).
				Where("user_id = ? AND friend_id = ? AND status = ?", senderID, receiverID, model.StatusPending).
				Update("status", model.StatusAccepted)
			if result.Error != nil {
				return result.Error
			}
			if result.RowsAffected == 0 {
				return errors.New("request not found")
			}
			reverse := &model.Friendship{
				UserID:   receiverID,
				FriendID: senderID,
				Status:   model.StatusAccepted,
			}
			return tx.Create(reverse).Error
		})
	}

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

// RemoveFriend удаляет дружбу в обе стороны.
func (r *FriendshipRepository) RemoveFriend(userID, friendID uint) error {
	return r.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where(
			"(user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)",
			userID, friendID, friendID, userID,
		).Delete(&model.Friendship{}).Error; err != nil {
			return err
		}
		return nil
	})
}

// BlockUser создаёт запись блокировки, удаляя дружбу если была.
func (r *FriendshipRepository) BlockUser(blockerID, targetID uint) error {
	return r.DB.Transaction(func(tx *gorm.DB) error {
		// Удаляем все записи между парой (и дружбу, и заявки)
		tx.Where(
			"(user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)",
			blockerID, targetID, targetID, blockerID,
		).Delete(&model.Friendship{})
		// Создаём запись блокировки
		block := &model.Friendship{
			UserID:   blockerID,
			FriendID: targetID,
			Status:   model.StatusBlocked,
		}
		return tx.Create(block).Error
	})
}

// UnblockUser удаляет запись блокировки.
func (r *FriendshipRepository) UnblockUser(blockerID, targetID uint) error {
	result := r.DB.Where("user_id = ? AND friend_id = ? AND status = ?", blockerID, targetID, model.StatusBlocked).
		Delete(&model.Friendship{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return errors.New("block not found")
	}
	return nil
}

// IsBlocked проверяет, заблокировал ли blockerID пользователя targetID.
func (r *FriendshipRepository) IsBlocked(blockerID, targetID uint) bool {
	var count int64
	r.DB.Model(&model.Friendship{}).
		Where("user_id = ? AND friend_id = ? AND status = ?", blockerID, targetID, model.StatusBlocked).
		Count(&count)
	return count > 0
}

// GetBlockedUsers возвращает список заблокированных пользователей.
func (r *FriendshipRepository) GetBlockedUsers(userID uint) ([]dto.Friend, error) {
	var users []dto.Friend
	err := r.DB.Table("friendships").
		Select("users.id, users.username, users.avatar_url").
		Joins("JOIN users ON users.id = friendships.friend_id").
		Where("friendships.user_id = ? AND friendships.status = ? AND users.deleted_at IS NULL", userID, model.StatusBlocked).
		Scan(&users).Error
	return users, err
}

// UpdateLastSeen обновляет время последней активности пользователя.
func (r *FriendshipRepository) UpdateLastSeen(userID uint) error {
	return r.DB.Model(&model.User{}).Where("id = ?", userID).
		Update("last_seen_at", time.Now()).Error
}

// GetSentPendingRequests возвращает пользователей, которым текущий пользователь отправил заявку.
func (r *FriendshipRepository) GetSentPendingRequests(userID uint) ([]dto.Friend, error) {
	var friends []dto.Friend
	err := r.DB.Table("friendships").
		Select("users.id, users.username, users.avatar_url").
		Joins("JOIN users ON users.id = friendships.friend_id").
		Where("friendships.user_id = ? AND friendships.status = ? AND users.deleted_at IS NULL", userID, model.StatusPending).
		Scan(&friends).Error
	return friends, err
}

// GetFriendIDs возвращает только ID друзей — используется для рассылки presence.
func (r *FriendshipRepository) GetFriendIDs(userID uint) ([]uint, error) {
	var ids []uint
	err := r.DB.Model(&model.Friendship{}).
		Where("user_id = ? AND status = ?", userID, model.StatusAccepted).
		Pluck("friend_id", &ids).Error
	return ids, err
}

// GetFriendshipStatus возвращает статус отношений между двумя пользователями.
func (r *FriendshipRepository) GetFriendshipStatus(myID, targetID uint) string {
	var f model.Friendship

	if err := r.DB.Where("user_id = ? AND friend_id = ? AND status = ?", myID, targetID, model.StatusAccepted).
		First(&f).Error; err == nil {
		return "friends"
	}
	if err := r.DB.Where("user_id = ? AND friend_id = ? AND status = ?", myID, targetID, model.StatusPending).
		First(&f).Error; err == nil {
		return "pending_outgoing"
	}
	if err := r.DB.Where("user_id = ? AND friend_id = ? AND status = ?", targetID, myID, model.StatusPending).
		First(&f).Error; err == nil {
		return "pending_incoming"
	}
	if err := r.DB.Where("user_id = ? AND friend_id = ? AND status = ?", myID, targetID, model.StatusBlocked).
		First(&f).Error; err == nil {
		return "blocked"
	}
	return "none"
}

// GetFriends возвращает список друзей пользователя.
func (r *FriendshipRepository) GetFriends(userID uint) ([]dto.Friend, error) {
	var friends []dto.Friend
	err := r.DB.Table("friendships").
		Select("users.id, users.username, users.avatar_url").
		Joins("JOIN users ON users.id = friendships.friend_id").
		Where("friendships.user_id = ? AND friendships.status = ? AND users.deleted_at IS NULL", userID, model.StatusAccepted).
		Scan(&friends).Error
	return friends, err
}
