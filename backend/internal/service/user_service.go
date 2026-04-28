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

func (s *UserService) UpdateUser(userDTO dto.User) error {
	existingUser, err := s.repo.GetUserById(userDTO.ID)
	if err != nil {
		return err
	}

	existingUser.Username = userDTO.Username

	if userDTO.Password != "" {
		hashedPassword, err := bcrypt.GenerateFromPassword([]byte(userDTO.Password), bcrypt.DefaultCost)
		if err != nil {
			return err
		}
		existingUser.PasswordHash = hashedPassword
	}

	return s.repo.UpdateUser(existingUser)
}

/* func (s *UserService) ChangePassword(id uint, passDTO model.PasswordDTO) error {
	user, err := s.repo.GetUserById(id)
	if err != nil {
		return err
	}

	if err := bcrypt.CompareHashAndPassword(user.PasswordHash, []byte(passDTO.CurrPass)); err != nil {
		return err
	}

	newHashedPassword, err := bcrypt.GenerateFromPassword([]byte(passDTO.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	user.PasswordHash = newHashedPassword

	err = s.repo.UpdateUser(user)
	return err
} */

func (s *UserService) GetUserByID(id uint) (*dto.User, error) {
	user, err := s.repo.GetUserById(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("user not found")
		}
		log.Printf("error get user %d: %v", id, err)
		return nil, err
	}

	userDTO := &dto.User{
		ID:       user.ID,
		Username: user.Username,
	}

	return userDTO, nil
}

func (s *UserService) GetUsers() ([]dto.User, error) {
	users, err := s.repo.GetUsers()
	if err != nil {
		return nil, err
	}

	var usersDTO []dto.User
	for _, u := range users {
		userDTO := &dto.User{
			ID:       u.ID,
			Username: u.Username,
		}

		usersDTO = append(usersDTO, *userDTO)
	}

	return usersDTO, nil
}

func (s *UserService) DeleteUser(idString string) error {
	id, err := strconv.Atoi(idString)
	if err != nil {
		return err
	}

	return s.repo.DeleteUser(uint(id))
}
