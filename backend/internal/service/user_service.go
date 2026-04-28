package service

import (
	dto "cove/internal/DTO"
	"cove/internal/model"
	"cove/internal/repository"
	"errors"
	"log"
	"strconv"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

type UserService struct {
	repo *repository.UserRepository
}

func NewUserService(repo *repository.UserRepository) *UserService {
	return &UserService{repo: repo}
}

func (s *UserService) GetUserByUsername(username string) (model.User, error) {
	return s.repo.GetUserByUsername(username)
}

func (s *UserService) GetPublicUserByUsername(username string) (*dto.User, error) {
	user, err := s.repo.GetUserByUsername(username)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("user not found")
		}
		return nil, err
	}
	return &dto.User{ID: user.ID, Username: user.Username}, nil
}

func (s *UserService) SearchUser(query string) (*dto.User, error) {
	user, err := s.repo.GetUserByUsername(query)
	if err == nil {
		return &dto.User{ID: user.ID, Username: user.Username}, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}

	id, parseErr := strconv.ParseUint(query, 10, 32)
	if parseErr != nil {
		return nil, errors.New("user not found")
	}

	return s.GetUserByID(uint(id))
}

func (s *UserService) CreateUser(userDTO dto.User) error {
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(userDTO.Password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	user := &model.User{
		Username:     userDTO.Username,
		PasswordHash: hashedPassword,
	}

	return s.repo.CreateUser(user)
}

func (s *UserService) GetUserByID(id uint) (*dto.User, error) {
	user, err := s.repo.GetUserById(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("user not found")
		}
		log.Printf("error get user %d: %v", id, err)
		return nil, err
	}

	return &dto.User{ID: user.ID, Username: user.Username}, nil
}
