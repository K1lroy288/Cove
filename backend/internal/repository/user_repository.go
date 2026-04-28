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
