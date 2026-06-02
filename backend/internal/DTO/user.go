package dto

import "time"

type User struct {
	ID        uint    `json:"id"`
	Username  string  `json:"username" binding:"required,min=3,max=32"`
	Password  string  `json:"password" binding:"required,min=8,max=72"`
	AvatarURL *string `json:"avatar_url,omitempty"`
}

type MyProfileDTO struct {
	ID          uint      `json:"id"`
	Username    string    `json:"username"`
	Bio         *string   `json:"bio"`
	AvatarURL   *string   `json:"avatar_url,omitempty"`
	MemberSince time.Time `json:"member_since"`
}

type UserProfileDTO struct {
	ID               uint      `json:"id"`
	Username         string    `json:"username"`
	Bio              *string   `json:"bio"`
	AvatarURL        *string   `json:"avatar_url,omitempty"`
	MemberSince      time.Time `json:"member_since"`
	FriendshipStatus string    `json:"friendship_status"`
}

type UpdateProfileRequest struct {
	Username  *string `json:"username"   binding:"omitempty,min=3,max=32"`
	Bio       *string `json:"bio"        binding:"omitempty,max=500"`
	AvatarURL *string `json:"avatar_url" binding:"omitempty,max=512"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password" binding:"required,min=1"`
	NewPassword     string `json:"new_password"     binding:"required,min=8,max=72"`
}
