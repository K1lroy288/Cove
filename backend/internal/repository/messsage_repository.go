package repository

import (
	"cove/internal/model"
	"fmt"

	"gorm.io/gorm"
)

type MessageRepository struct {
	DB *gorm.DB
}

func NewMessageRepository(db *gorm.DB) *MessageRepository {
	return &MessageRepository{DB: db}
}

// GetMessages возвращает limit сообщений чата в хронологическом порядке.
// Если beforeID задан — возвращает сообщения с id < beforeID (подгрузка истории вверх).
func (r *MessageRepository) GetMessages(chatID uint, beforeID *uint, limit int) ([]model.Message, error) {
	q := r.DB.Where("chat_id = ? AND deleted_at IS NULL", chatID)
	if beforeID != nil {
		q = q.Where("id < ?", *beforeID)
	}

	var messages []model.Message
	err := q.Order("id DESC").Limit(limit).Find(&messages).Error
	if err != nil {
		return nil, err
	}

	// Разворачиваем: БД отдаёт DESC для эффективного LIMIT, клиент ждёт хронологию.
	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	return messages, nil
}

// SaveMessage сохраняет сообщение и обновляет денормализованные поля чата в одной транзакции.
func (r *MessageRepository) SaveMessage(chatID, senderID uint, content, msgType string) (model.Message, error) {
	msg := model.Message{
		ChatID:   chatID,
		SenderID: senderID,
		Content:  content,
		Type:     msgType,
	}
	err := r.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&msg).Error; err != nil {
			return err
		}
		return tx.Model(&model.Chat{}).Where("id = ?", chatID).Updates(map[string]any{
			"last_message_id":      msg.ID,
			"last_message_at":      msg.CreatedAt,
			"last_message_content": content,
		}).Error
	})
	return msg, err
}

// IsDMChat возвращает true, если чат является личным (dm).
func (r *MessageRepository) IsDMChat(chatID uint) (bool, error) {
	var chatType string
	err := r.DB.Table("chats").Select("chat_type").Where("id = ?", chatID).Scan(&chatType).Error
	if err != nil {
		return false, err
	}
	return chatType == "dm", nil
}

// IsChatMember проверяет, является ли пользователь участником чата.
func (r *MessageRepository) IsChatMember(chatID, userID uint) (bool, error) {
	var count int64
	err := r.DB.Table("chat_members").
		Where("chat_id = ? AND user_id = ?", chatID, userID).
		Count(&count).Error
	return count > 0, err
}

// GetPartnerID возвращает ID второго участника DM-чата.
func (r *MessageRepository) GetPartnerID(chatID, senderID uint) (uint, error) {
	var partnerID uint
	err := r.DB.Table("chat_members").
		Select("user_id").
		Where("chat_id = ? AND user_id != ?", chatID, senderID).
		Limit(1).
		Scan(&partnerID).Error
	if err != nil {
		return 0, err
	}
	if partnerID == 0 {
		return 0, fmt.Errorf("partner not found for chat %d", chatID)
	}
	return partnerID, nil
}

// GetChatMemberIDs возвращает всех участников чата (работает и для DM и для групп).
func (r *MessageRepository) GetChatMemberIDs(chatID uint) ([]uint, error) {
	var ids []uint
	err := r.DB.Table("chat_members").
		Where("chat_id = ?", chatID).
		Pluck("user_id", &ids).Error
	return ids, err
}

// GetMessageSenderID возвращает sender_id для сообщения.
func (r *MessageRepository) GetMessageSenderID(messageID uint) (uint, error) {
	var senderID uint
	err := r.DB.Table("messages").
		Select("sender_id").
		Where("id = ?", messageID).
		Scan(&senderID).Error
	if err != nil {
		return 0, err
	}
	if senderID == 0 {
		return 0, fmt.Errorf("message %d not found", messageID)
	}
	return senderID, nil
}

// UpsertDeliveredCursor обновляет last_delivered_message_id, двигая только вперёд.
func (r *MessageRepository) UpsertDeliveredCursor(chatID, userID, messageID uint) error {
	return r.DB.Exec(`
		INSERT INTO chat_read_cursors (chat_id, user_id, last_delivered_message_id, updated_at)
		VALUES (?, ?, ?, NOW())
		ON CONFLICT (chat_id, user_id) DO UPDATE SET
			last_delivered_message_id = GREATEST(EXCLUDED.last_delivered_message_id, COALESCE(chat_read_cursors.last_delivered_message_id, 0)),
			updated_at = NOW()
	`, chatID, userID, messageID).Error
}

// UpsertReadCursor обновляет last_read_message_id и last_delivered_message_id, двигая только вперёд.
func (r *MessageRepository) UpsertReadCursor(chatID, userID, messageID uint) error {
	return r.DB.Exec(`
		INSERT INTO chat_read_cursors (chat_id, user_id, last_read_message_id, last_delivered_message_id, updated_at)
		VALUES (?, ?, ?, ?, NOW())
		ON CONFLICT (chat_id, user_id) DO UPDATE SET
			last_read_message_id = GREATEST(EXCLUDED.last_read_message_id, COALESCE(chat_read_cursors.last_read_message_id, 0)),
			last_delivered_message_id = GREATEST(EXCLUDED.last_delivered_message_id, COALESCE(chat_read_cursors.last_delivered_message_id, 0)),
			updated_at = NOW()
	`, chatID, userID, messageID, messageID).Error
}

// GetPartnerCursor возвращает курсор партнёра в DM-чате (для отображения статуса своих сообщений).
func (r *MessageRepository) GetPartnerCursor(chatID, myUserID uint) (*model.ChatReadCursor, error) {
	var cursor model.ChatReadCursor
	err := r.DB.Where("chat_id = ? AND user_id != ?", chatID, myUserID).
		First(&cursor).Error
	if err != nil {
		return nil, err
	}
	return &cursor, nil
}
