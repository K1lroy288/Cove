package repository

import (
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

// FindExistingChat ищет DM-чат между двумя пользователями, возвращает его ID или 0.
func (r *ChatRepository) FindExistingChat(userID, friendID uint) (uint, error) {
	var chatID uint
	err := r.DB.Raw(`
		SELECT c.id FROM chats c
		JOIN chat_members cm1 ON cm1.chat_id = c.id AND cm1.user_id = ?
		JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id = ?
		LIMIT 1
	`, userID, friendID).Scan(&chatID).Error
	return chatID, err
}

// CreateChat создаёт новый чат и добавляет обоих участников в одной транзакции.
func (r *ChatRepository) CreateChat(userID, friendID uint) (*model.Chat, error) {
	chat := &model.Chat{}
	err := r.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(chat).Error; err != nil {
			return err
		}
		members := []model.ChatMember{
			{ChatID: chat.ID, UserID: userID},
			{ChatID: chat.ID, UserID: friendID},
		}
		return tx.Create(&members).Error
	})
	return chat, err
}

// GetChatDTO возвращает полный DTO чата для указанного пользователя.
// Используется как после создания, так и при нахождении существующего чата.
func (r *ChatRepository) GetChatDTO(chatID, myUserID uint) (*dto.ChatDTO, error) {
	var result dto.ChatDTO
	err := r.DB.Raw(`
		SELECT
			c.id,
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
		WHERE c.id = ?
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

// GetChats возвращает все чаты пользователя с данными партнёра и счётчиком непрочитанных.
func (r *ChatRepository) GetChats(userID uint) ([]dto.ChatDTO, error) {
	var chats []dto.ChatDTO
	err := r.DB.Raw(`
		SELECT
			c.id,
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
		JOIN chat_members cm  ON cm.chat_id = c.id AND cm.user_id = ?
		JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id != ?
		JOIN users u          ON u.id = cm2.user_id AND u.deleted_at IS NULL
		LEFT JOIN chat_read_cursors crc ON crc.chat_id = c.id AND crc.user_id = ?
		ORDER BY c.last_message_at DESC NULLS LAST
	`, userID, userID, userID).Scan(&chats).Error
	if chats == nil {
		chats = []dto.ChatDTO{}
	}
	return chats, err
}
