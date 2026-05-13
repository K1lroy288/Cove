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

// IsChatMember проверяет, является ли пользователь участником чата.
func (r *MessageRepository) IsChatMember(chatID, userID uint) (bool, error) {
	var count int64
	err := r.DB.Table("chat_members").
		Where("chat_id = ? AND user_id = ?", chatID, userID).
		Count(&count).Error
	return count > 0, err
}

// GetPartnerID возвращает ID второго участника чата.
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
