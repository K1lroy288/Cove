package service

import (
	dto "cove/internal/DTO"
	"cove/internal/repository"
	"errors"
)

var (
	ErrNotFriends          = errors.New("not friends")
	ErrNotAdmin            = errors.New("not an admin")
	ErrNotMember           = errors.New("not a member")
	ErrGroupFull           = errors.New("group is full (max 15 members)")
	ErrGroupTooSmall       = errors.New("group needs at least 3 members")
	ErrNotGroupChat        = errors.New("not a group chat")
	ErrTargetNotFriendable = errors.New("target user is not friends with any admin")
)

type ChatService struct {
	repo *repository.ChatRepository
}

func NewChatService(repo *repository.ChatRepository) *ChatService {
	return &ChatService{repo: repo}
}

func (s *ChatService) GetChats(userID uint) ([]dto.ChatDTO, error) {
	return s.repo.GetChats(userID)
}

// CreateOrGetChat возвращает существующий DM-чат или создаёт новый.
// Второй возврат — true если чат только что создан (201), false если уже существовал (200).
func (s *ChatService) CreateOrGetChat(myUserID, friendID uint) (*dto.ChatDTO, bool, error) {
	isFriend, err := s.repo.IsFriend(myUserID, friendID)
	if err != nil {
		return nil, false, err
	}
	if !isFriend {
		return nil, false, ErrNotFriends
	}

	existingID, err := s.repo.FindExistingChat(myUserID, friendID)
	if err != nil {
		return nil, false, err
	}
	if existingID != 0 {
		chat, err := s.repo.GetChatDTO(existingID, myUserID)
		return chat, false, err
	}

	newChat, err := s.repo.CreateChat(myUserID, friendID)
	if err != nil {
		return nil, false, err
	}
	chat, err := s.repo.GetChatDTO(newChat.ID, myUserID)
	return chat, true, err
}

// CreateGroup создаёт новую группу.
// Все memberIDs должны быть друзьями creatorID.
func (s *ChatService) CreateGroup(creatorID uint, req dto.CreateGroupRequest) (*dto.ChatDTO, []uint, error) {
	if len(req.MemberIDs) < 2 {
		return nil, nil, ErrGroupTooSmall
	}
	if len(req.MemberIDs) > 14 {
		return nil, nil, ErrGroupFull
	}

	allFriends, err := s.repo.AreFriendsWithCreator(creatorID, req.MemberIDs)
	if err != nil {
		return nil, nil, err
	}
	if !allFriends {
		return nil, nil, ErrNotFriends
	}

	chat, err := s.repo.CreateGroupChat(creatorID, req.Name, req.Avatar, req.MemberIDs)
	if err != nil {
		return nil, nil, err
	}

	chatDTO, err := s.repo.GetGroupChatDTO(chat.ID, creatorID)
	if err != nil {
		return nil, nil, err
	}

	allMemberIDs := append([]uint{creatorID}, req.MemberIDs...)
	return chatDTO, allMemberIDs, nil
}

// GetGroupMembers возвращает список участников. Вызывающий должен быть участником.
func (s *ChatService) GetGroupMembers(chatID, callerID uint) ([]dto.GroupMemberDTO, error) {
	role, err := s.repo.GetMemberRole(chatID, callerID)
	if err != nil {
		return nil, err
	}
	if role == "" {
		return nil, ErrNotMember
	}
	return s.repo.GetGroupMembers(chatID)
}

// AddMembers добавляет участников. Вызывающий должен быть admin.
// Каждый новый участник должен быть другом хотя бы одного admin.
func (s *ChatService) AddMembers(chatID, callerID uint, userIDs []uint) error {
	role, err := s.repo.GetMemberRole(chatID, callerID)
	if err != nil {
		return err
	}
	if role != "admin" {
		return ErrNotAdmin
	}

	currentCount, err := s.repo.GetGroupMemberCount(chatID)
	if err != nil {
		return err
	}
	if currentCount+len(userIDs) > 15 {
		return ErrGroupFull
	}

	for _, uid := range userIDs {
		ok, err := s.repo.IsAdminFriendWithUser(chatID, uid)
		if err != nil {
			return err
		}
		if !ok {
			return ErrTargetNotFriendable
		}
	}

	return s.repo.AddGroupMembers(chatID, userIDs)
}

// KickMember удаляет участника. Вызывающий — admin, нельзя кикнуть себя.
func (s *ChatService) KickMember(chatID, callerID, targetID uint) error {
	if callerID == targetID {
		return errors.New("use LeaveGroup to leave")
	}
	role, err := s.repo.GetMemberRole(chatID, callerID)
	if err != nil {
		return err
	}
	if role != "admin" {
		return ErrNotAdmin
	}
	_, err = s.repo.RemoveMember(chatID, targetID)
	return err
}

// LeaveGroup выходит из группы. Возвращает (dissolved, err).
func (s *ChatService) LeaveGroup(chatID, callerID uint) (bool, error) {
	role, err := s.repo.GetMemberRole(chatID, callerID)
	if err != nil {
		return false, err
	}
	if role == "" {
		return false, ErrNotMember
	}
	return s.repo.RemoveMember(chatID, callerID)
}

// DeleteGroup удаляет группу. Вызывающий — admin.
func (s *ChatService) DeleteGroup(chatID, callerID uint) error {
	role, err := s.repo.GetMemberRole(chatID, callerID)
	if err != nil {
		return err
	}
	if role != "admin" {
		return ErrNotAdmin
	}
	return s.repo.DeleteGroup(chatID)
}

// UpdateGroup обновляет название/аватар. Вызывающий — admin.
func (s *ChatService) UpdateGroup(chatID, callerID uint, req dto.UpdateGroupRequest) (*dto.ChatDTO, error) {
	role, err := s.repo.GetMemberRole(chatID, callerID)
	if err != nil {
		return nil, err
	}
	if role != "admin" {
		return nil, ErrNotAdmin
	}
	if err := s.repo.UpdateGroupInfo(chatID, req.Name, req.Avatar); err != nil {
		return nil, err
	}
	return s.repo.GetGroupChatDTO(chatID, callerID)
}

// SetMemberRole меняет роль участника. Вызывающий — admin.
func (s *ChatService) SetMemberRole(chatID, callerID, targetID uint, role string) error {
	if role != "member" && role != "admin" {
		return errors.New("invalid role")
	}
	callerRole, err := s.repo.GetMemberRole(chatID, callerID)
	if err != nil {
		return err
	}
	if callerRole != "admin" {
		return ErrNotAdmin
	}
	targetRole, err := s.repo.GetMemberRole(chatID, targetID)
	if err != nil {
		return err
	}
	if targetRole == "" {
		return ErrNotMember
	}
	return s.repo.SetMemberRole(chatID, targetID, role)
}

// GetGroupMemberIDs возвращает всех участников группы (нужно для WS-уведомлений).
func (s *ChatService) GetGroupMemberIDs(chatID uint) ([]uint, error) {
	return s.repo.GetGroupMemberIDs(chatID)
}

// GetChatType возвращает тип чата.
func (s *ChatService) GetChatType(chatID uint) (string, error) {
	return s.repo.GetChatType(chatID)
}
