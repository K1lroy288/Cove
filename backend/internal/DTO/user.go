package dto

import "time"

type User struct {
	ID       uint   `json:"id"`
	Username string `json:"username"`
	Password string `json:"password"`
}

type MyProfileDTO struct {
	ID          uint      `json:"id"`
	Username    string    `json:"username"`
	Bio         *string   `json:"bio"`
	MemberSince time.Time `json:"member_since"`
}

type UserProfileDTO struct {
	ID               uint      `json:"id"`
	Username         string    `json:"username"`
	Bio              *string   `json:"bio"`
	MemberSince      time.Time `json:"member_since"`
	FriendshipStatus string    `json:"friendship_status"`
}

type UpdateProfileRequest struct {
	Username *string `json:"username"`
	Bio      *string `json:"bio"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}
