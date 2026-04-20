package repository

import (
	"cove/internal/model"
	"time"

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

func (r *UserRepository) UpdateUser(user *model.User) error {
	return r.DB.Save(user).Error
}

func (r *UserRepository) DeleteUser(id uint) error {
	return r.DB.Model(&model.User{ID: id}).Update("deleted_at", time.Now()).Error
}

func (r *UserRepository) GetUsers() ([]model.User, error) {
	var users []model.User
	err := r.DB.
		Table("users").
		//Preload("Roles").
		Where("deleted_at IS NULL").
		Find(&users).
		Error

	return users, err
}

func (r *UserRepository) GetUserById(id uint) (*model.User, error) {
	var user *model.User
	err := r.DB.Model(&model.User{ID: id}).Scan(&user).Error
	return user, err
}
