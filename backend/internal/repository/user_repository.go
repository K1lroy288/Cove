package repository

import (
	"cove/internal/model"

	"gorm.io/gorm"
)

type UserRepository struct {
	DB *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserRepository {
	return &UserRepository{DB: db}
}

func (r *UserRepository) CreateUser(user *model.User) error {
	return r.DB.Create(user).Error
}

func (r *UserRepository) GetUserByUsername(username string) (model.User, error) {
	var user model.User
	err := r.DB.Where("username = ?", username).First(&user).Error
	return user, err
}

func (r *UserRepository) GetUserById(id uint) (*model.User, error) {
	var user *model.User
	err := r.DB.Model(&model.User{ID: id}).Scan(&user).Error
	return user, err
}

func (r *UserRepository) UpdateUser(id uint, username *string, bio *string, avatarURL *string) error {
	updates := map[string]interface{}{}
	if username != nil {
		updates["username"] = *username
	}
	if bio != nil {
		updates["bio"] = *bio
	}
	if avatarURL != nil {
		updates["avatar_url"] = *avatarURL
	}
	if len(updates) == 0 {
		return nil
	}
	return r.DB.Model(&model.User{}).Where("id = ? AND deleted_at IS NULL", id).Updates(updates).Error
}

func (r *UserRepository) UpdatePasswordHash(id uint, hash []byte) error {
	return r.DB.Model(&model.User{}).Where("id = ? AND deleted_at IS NULL", id).
		Update("password_hash", hash).Error
}

func (r *UserRepository) SoftDeleteUser(id uint) error {
	return r.DB.Delete(&model.User{}, id).Error
}
