package dto

type Friendship struct {
	UserID   uint   `json:"user_id"`
	FriendID uint   `json:"friend_id"`
	Status   string `json:"status"`
}
