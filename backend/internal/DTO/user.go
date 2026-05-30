package dto

import "time"

type User struct {
	ID        uint    `json:"id"`
	Username  string  `json:"username"`
	Password  string  `json:"password"`
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
	Username  *string `json:"username"`
	Bio       *string `json:"bio"`
	AvatarURL *string `json:"avatar_url"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}
