package dto

import "time"

type ChatDTO struct {
	ID                uint       `json:"id"`
	ChatType          string     `json:"chat_type"`
	// DM fields (zero for groups)
	PartnerID         uint       `json:"partner_id"`
	PartnerName       string     `json:"partner_name"`
	PartnerAvatarURL  *string    `json:"partner_avatar_url,omitempty"`
	// Group fields (zero for DMs)
	GroupName         string     `json:"group_name,omitempty"`
	GroupAvatar       string     `json:"group_avatar,omitempty"`
	MemberCount       int        `json:"member_count,omitempty"`
	MyRole            string     `json:"my_role,omitempty"`
	// Shared
	LastMessage       *string           `json:"last_message"`
	LastMessageAt     *time.Time        `json:"last_message_at"`
	UnreadCount       int               `json:"unread_count"`
	PinnedMessage     *PinnedMessageDTO `json:"pinned_message,omitempty" gorm:"-"`
}

type CreateChatRequest struct {
	FriendID uint `json:"friend_id" binding:"required"`
}

type CreateGroupRequest struct {
	Name      string `json:"name"       binding:"required,min=1,max=100"`
	Avatar    string `json:"avatar"`
	MemberIDs []uint `json:"member_ids" binding:"required,min=2,max=14"`
}

type UpdateGroupRequest struct {
	Name   *string `json:"name"   binding:"omitempty,min=1,max=100"`
	Avatar *string `json:"avatar" binding:"omitempty,max=512"`
}

type AddMembersRequest struct {
	UserIDs []uint `json:"user_ids" binding:"required,min=1"`
}

type GroupMemberDTO struct {
	UserID    uint   `json:"user_id"`
	Username  string `json:"username"`
	Role      string `json:"role"`
	JoinedAt  string `json:"joined_at"`
	AvatarURL string `json:"avatar_url"`
}
