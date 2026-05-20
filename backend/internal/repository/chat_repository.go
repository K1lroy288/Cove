package repository

import (
	"fmt"

	dto "cove/internal/DTO"
	"cove/internal/model"

	"gorm.io/gorm"
)

type ChatRepository struct {
	DB *gorm.DB
}

func NewChatRepository(db *gorm.DB) *ChatRepository {
	return &ChatRepository{DB: db}
}

func (r *ChatRepository) IsFriend(userID, friendID uint) (bool, error) {
	var count int64
	err := r.DB.Model(&model.Friendship{}).
		Where("user_id = ? AND friend_id = ? AND status = ?", userID, friendID, model.StatusAccepted).
		Count(&count).Error
	return count > 0, err
}

// FindExistingChat ищет DM-чат между двумя пользователями.
func (r *ChatRepository) FindExistingChat(userID, friendID uint) (uint, error) {
	var chatID uint
	err := r.DB.Raw(`
		SELECT c.id FROM chats c
		JOIN chat_members cm1 ON cm1.chat_id = c.id AND cm1.user_id = ?
		JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id = ?
		WHERE c.chat_type = 'dm'
		LIMIT 1
	`, userID, friendID).Scan(&chatID).Error
	return chatID, err
}

// CreateChat создаёт новый DM-чат и добавляет обоих участников в одной транзакции.
func (r *ChatRepository) CreateChat(userID, friendID uint) (*model.Chat, error) {
	chat := &model.Chat{ChatType: "dm"}
	err := r.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(chat).Error; err != nil {
			return err
		}
		members := []model.ChatMember{
			{ChatID: chat.ID, UserID: userID, Role: "member"},
			{ChatID: chat.ID, UserID: friendID, Role: "member"},
		}
		return tx.Create(&members).Error
	})
	return chat, err
}

// GetChatDTO возвращает DTO для DM-чата.
func (r *ChatRepository) GetChatDTO(chatID, myUserID uint) (*dto.ChatDTO, error) {
	var result dto.ChatDTO
	err := r.DB.Raw(`
		SELECT
			c.id,
			'dm'               AS chat_type,
			u.id               AS partner_id,
			u.username         AS partner_name,
			c.last_message_content AS last_message,
			c.last_message_at,
			COALESCE(
				(SELECT COUNT(*) FROM messages m
				 WHERE m.chat_id = c.id
				   AND m.id > COALESCE(crc.last_read_message_id, 0)
				   AND m.deleted_at IS NULL),
				0
			) AS unread_count
		FROM chats c
		JOIN chat_members cm1 ON cm1.chat_id = c.id AND cm1.user_id = ?
		JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id != ?
		JOIN users u          ON u.id = cm2.user_id AND u.deleted_at IS NULL
		LEFT JOIN chat_read_cursors crc ON crc.chat_id = c.id AND crc.user_id = ?
		WHERE c.id = ? AND c.chat_type = 'dm'
		LIMIT 1
	`, myUserID, myUserID, myUserID, chatID).Scan(&result).Error
	if err != nil {
		return nil, err
	}
	if result.ID == 0 {
		return nil, nil
	}
	return &result, nil
}

// GetGroupChatDTO возвращает DTO для группового чата.
func (r *ChatRepository) GetGroupChatDTO(chatID, myUserID uint) (*dto.ChatDTO, error) {
	var result dto.ChatDTO
	err := r.DB.Raw(`
		SELECT
			c.id,
			'group'            AS chat_type,
			c.name             AS group_name,
			COALESCE(c.avatar, '') AS group_avatar,
			(SELECT COUNT(*) FROM chat_members gcm WHERE gcm.chat_id = c.id) AS member_count,
			cm.role            AS my_role,
			c.last_message_content AS last_message,
			c.last_message_at,
			COALESCE(
				(SELECT COUNT(*) FROM messages m
				 WHERE m.chat_id = c.id
				   AND m.id > COALESCE(crc.last_read_message_id, 0)
				   AND m.deleted_at IS NULL),
				0
			) AS unread_count
		FROM chats c
		JOIN chat_members cm ON cm.chat_id = c.id AND cm.user_id = ?
		LEFT JOIN chat_read_cursors crc ON crc.chat_id = c.id AND crc.user_id = ?
		WHERE c.id = ? AND c.chat_type = 'group'
		LIMIT 1
	`, myUserID, myUserID, chatID).Scan(&result).Error
	if err != nil {
		return nil, err
	}
	if result.ID == 0 {
		return nil, nil
	}
	return &result, nil
}

// GetChats возвращает все чаты пользователя (DM и группы) с непрочитанными.
func (r *ChatRepository) GetChats(userID uint) ([]dto.ChatDTO, error) {
	var chats []dto.ChatDTO
	err := r.DB.Raw(`
		SELECT
			c.id,
			'dm'               AS chat_type,
			u.id               AS partner_id,
			u.username         AS partner_name,
			''                 AS group_name,
			''                 AS group_avatar,
			0                  AS member_count,
			'member'           AS my_role,
			c.last_message_content AS last_message,
			c.last_message_at,
			COALESCE(
				(SELECT COUNT(*) FROM messages m
				 WHERE m.chat_id = c.id
				   AND m.id > COALESCE(crc.last_read_message_id, 0)
				   AND m.deleted_at IS NULL),
				0
			) AS unread_count
		FROM chats c
		JOIN chat_members cm  ON cm.chat_id = c.id AND cm.user_id = ?
		JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id != ?
		JOIN users u          ON u.id = cm2.user_id AND u.deleted_at IS NULL
		LEFT JOIN chat_read_cursors crc ON crc.chat_id = c.id AND crc.user_id = ?
		WHERE c.chat_type = 'dm'

		UNION ALL

		SELECT
			c.id,
			'group'            AS chat_type,
			0                  AS partner_id,
			''                 AS partner_name,
			c.name             AS group_name,
			COALESCE(c.avatar, '') AS group_avatar,
			(SELECT COUNT(*) FROM chat_members gcm WHERE gcm.chat_id = c.id) AS member_count,
			cm.role            AS my_role,
			c.last_message_content AS last_message,
			c.last_message_at,
			COALESCE(
				(SELECT COUNT(*) FROM messages m
				 WHERE m.chat_id = c.id
				   AND m.id > COALESCE(crc.last_read_message_id, 0)
				   AND m.deleted_at IS NULL),
				0
			) AS unread_count
		FROM chats c
		JOIN chat_members cm ON cm.chat_id = c.id AND cm.user_id = ?
		LEFT JOIN chat_read_cursors crc ON crc.chat_id = c.id AND crc.user_id = ?
		WHERE c.chat_type = 'group'

		ORDER BY last_message_at DESC NULLS LAST
	`, userID, userID, userID, userID, userID).Scan(&chats).Error
	if chats == nil {
		chats = []dto.ChatDTO{}
	}
	return chats, err
}

// --- Группы ---

// CreateGroupChat создаёт групповой чат и добавляет участников в транзакции.
// Создатель получает роль admin, остальные — member.
func (r *ChatRepository) CreateGroupChat(creatorID uint, name, avatar string, memberIDs []uint) (*model.Chat, error) {
	chat := &model.Chat{
		ChatType:  "group",
		Name:      &name,
		CreatedBy: &creatorID,
	}
	if avatar != "" {
		chat.Avatar = &avatar
	}
	err := r.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(chat).Error; err != nil {
			return err
		}
		members := make([]model.ChatMember, 0, len(memberIDs)+1)
		members = append(members, model.ChatMember{ChatID: chat.ID, UserID: creatorID, Role: "admin"})
		for _, uid := range memberIDs {
			members = append(members, model.ChatMember{ChatID: chat.ID, UserID: uid, Role: "member"})
		}
		return tx.Create(&members).Error
	})
	return chat, err
}

// GetGroupMembers возвращает список участников группы.
func (r *ChatRepository) GetGroupMembers(chatID uint) ([]dto.GroupMemberDTO, error) {
	var members []dto.GroupMemberDTO
	err := r.DB.Raw(`
		SELECT cm.user_id, u.username, cm.role,
		       TO_CHAR(cm.joined_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS joined_at
		FROM chat_members cm
		JOIN users u ON u.id = cm.user_id AND u.deleted_at IS NULL
		WHERE cm.chat_id = ?
		ORDER BY cm.joined_at ASC
	`, chatID).Scan(&members).Error
	if members == nil {
		members = []dto.GroupMemberDTO{}
	}
	return members, err
}

// GetMemberRole возвращает роль пользователя в чате. Пустая строка — не участник.
func (r *ChatRepository) GetMemberRole(chatID, userID uint) (string, error) {
	var role string
	err := r.DB.Raw(
		`SELECT role FROM chat_members WHERE chat_id = ? AND user_id = ? LIMIT 1`,
		chatID, userID,
	).Scan(&role).Error
	return role, err
}

// GetGroupMemberCount возвращает текущее количество участников группы.
func (r *ChatRepository) GetGroupMemberCount(chatID uint) (int, error) {
	var count int64
	err := r.DB.Model(&model.ChatMember{}).Where("chat_id = ?", chatID).Count(&count).Error
	return int(count), err
}

// AreFriendsWithCreator проверяет, что каждый из userIDs является другом creatorID.
func (r *ChatRepository) AreFriendsWithCreator(creatorID uint, userIDs []uint) (bool, error) {
	if len(userIDs) == 0 {
		return true, nil
	}
	var count int64
	err := r.DB.Model(&model.Friendship{}).
		Where("user_id = ? AND friend_id IN ? AND status = ?", creatorID, userIDs, model.StatusAccepted).
		Count(&count).Error
	return int(count) == len(userIDs), err
}

// IsAdminFriendWithUser проверяет, что хотя бы один admin группы является другом targetUserID.
func (r *ChatRepository) IsAdminFriendWithUser(chatID, targetUserID uint) (bool, error) {
	var count int64
	err := r.DB.Raw(`
		SELECT COUNT(*) FROM chat_members cm
		JOIN friendships f ON f.user_id = cm.user_id AND f.friend_id = ? AND f.status = 'accepted'
		WHERE cm.chat_id = ? AND cm.role = 'admin'
	`, targetUserID, chatID).Scan(&count).Error
	return count > 0, err
}

// AddGroupMembers добавляет новых участников в группу.
func (r *ChatRepository) AddGroupMembers(chatID uint, userIDs []uint) error {
	members := make([]model.ChatMember, 0, len(userIDs))
	for _, uid := range userIDs {
		members = append(members, model.ChatMember{ChatID: chatID, UserID: uid, Role: "member"})
	}
	return r.DB.Create(&members).Error
}

// RemoveMember удаляет участника из группы.
// Если после удаления нет администраторов — промоутит старейшего участника.
// Если группа пустая — удаляет чат. Возвращает dissolved=true в этом случае.
func (r *ChatRepository) RemoveMember(chatID, userID uint) (bool, error) {
	dissolved := false
	err := r.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("chat_id = ? AND user_id = ?", chatID, userID).
			Delete(&model.ChatMember{}).Error; err != nil {
			return err
		}

		var adminCount int64
		if err := tx.Model(&model.ChatMember{}).
			Where("chat_id = ? AND role = 'admin'", chatID).
			Count(&adminCount).Error; err != nil {
			return err
		}

		if adminCount == 0 {
			var memberCount int64
			if err := tx.Model(&model.ChatMember{}).
				Where("chat_id = ?", chatID).
				Count(&memberCount).Error; err != nil {
				return err
			}
			if memberCount == 0 {
				dissolved = true
				return tx.Delete(&model.Chat{}, chatID).Error
			}
			// Промоутим старейшего участника
			return tx.Exec(`
				UPDATE chat_members SET role = 'admin'
				WHERE chat_id = ? AND user_id = (
					SELECT user_id FROM chat_members
					WHERE chat_id = ? ORDER BY joined_at ASC LIMIT 1
				)
			`, chatID, chatID).Error
		}
		return nil
	})
	return dissolved, err
}

// SetMemberRole устанавливает роль участника.
func (r *ChatRepository) SetMemberRole(chatID, userID uint, role string) error {
	return r.DB.Model(&model.ChatMember{}).
		Where("chat_id = ? AND user_id = ?", chatID, userID).
		Update("role", role).Error
}

// UpdateGroupInfo обновляет название и/или аватар группы.
func (r *ChatRepository) UpdateGroupInfo(chatID uint, name, avatar *string) error {
	updates := map[string]interface{}{}
	if name != nil {
		updates["name"] = *name
	}
	if avatar != nil {
		updates["avatar"] = *avatar
	}
	if len(updates) == 0 {
		return nil
	}
	return r.DB.Model(&model.Chat{}).Where("id = ?", chatID).Updates(updates).Error
}

// DeleteGroup удаляет групповой чат (CASCADE удаляет членов и сообщения).
func (r *ChatRepository) DeleteGroup(chatID uint) error {
	return r.DB.Delete(&model.Chat{}, chatID).Error
}

// GetChatType возвращает тип чата: "dm" или "group".
func (r *ChatRepository) GetChatType(chatID uint) (string, error) {
	var chatType string
	err := r.DB.Raw(`SELECT chat_type FROM chats WHERE id = ? LIMIT 1`, chatID).Scan(&chatType).Error
	if chatType == "" && err == nil {
		return "", fmt.Errorf("chat not found")
	}
	return chatType, err
}

// GetGroupMemberIDs возвращает все user_id участников чата.
func (r *ChatRepository) GetGroupMemberIDs(chatID uint) ([]uint, error) {
	var ids []uint
	err := r.DB.Model(&model.ChatMember{}).
		Where("chat_id = ?", chatID).
		Pluck("user_id", &ids).Error
	return ids, err
}
