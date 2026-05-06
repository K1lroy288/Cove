package repository

import (
	"cove/internal/model"

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
