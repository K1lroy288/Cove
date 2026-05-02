package dto

type Friendship struct {
	UserID   uint   `json:"user_id"`
	FriendID uint   `json:"friend_id"`
	Status   string `json:"status"`
}

type FriendRequest struct {
	UserID   uint   `json:"user_id"`
	Username string `json:"username"`
}

type RespondToRequestDTO struct {
	Status string `json:"status" binding:"required"`
}

type Friend struct {
	ID       uint   `json:"id"`
	Username string `json:"username"`
}
