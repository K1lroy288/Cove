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
	repo           *repository.UserRepository
	friendshipRepo *repository.FriendshipRepository
}

func NewUserService(repo *repository.UserRepository, friendshipRepo *repository.FriendshipRepository) *UserService {
	return &UserService{repo: repo, friendshipRepo: friendshipRepo}
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

func (s *UserService) GetMe(id uint) (*dto.MyProfileDTO, error) {
	user, err := s.repo.GetUserById(id)
	if err != nil {
		return nil, errors.New("user not found")
	}
	return &dto.MyProfileDTO{
		ID:          user.ID,
		Username:    user.Username,
		Bio:         user.Bio,
		MemberSince: user.CreatedAt,
	}, nil
}

func (s *UserService) UpdateMe(id uint, req dto.UpdateProfileRequest) (*dto.MyProfileDTO, error) {
	if req.Username != nil && len(*req.Username) < 2 {
		return nil, errors.New("username too short")
	}
	if err := s.repo.UpdateUser(id, req.Username, req.Bio); err != nil {
		return nil, err
	}
	return s.GetMe(id)
}

func (s *UserService) ChangePassword(id uint, req dto.ChangePasswordRequest) error {
	user, err := s.repo.GetUserById(id)
	if err != nil {
		return errors.New("user not found")
	}
	if err := bcrypt.CompareHashAndPassword(user.PasswordHash, []byte(req.CurrentPassword)); err != nil {
		return errors.New("wrong password")
	}
	if len(req.NewPassword) < 6 {
		return errors.New("password too short")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	return s.repo.UpdatePasswordHash(id, hash)
}

func (s *UserService) DeleteMe(id uint) error {
	return s.repo.SoftDeleteUser(id)
}

func (s *UserService) GetUserProfile(myID, targetID uint) (*dto.UserProfileDTO, error) {
	user, err := s.repo.GetUserById(targetID)
	if err != nil || user == nil {
		return nil, errors.New("user not found")
	}
	status := s.friendshipRepo.GetFriendshipStatus(myID, targetID)
	return &dto.UserProfileDTO{
		ID:               user.ID,
		Username:         user.Username,
		Bio:              user.Bio,
		MemberSince:      user.CreatedAt,
		FriendshipStatus: status,
	}, nil
}
