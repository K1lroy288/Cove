package repository

import (
	"cove/internal/model"
	"fmt"
	"time"

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
func (r *MessageRepository) GetMessages(chatID uint, beforeID *uint, limit int, types []string) ([]model.Message, error) {
	q := r.DB.Where("chat_id = ?", chatID).
		Where("deleted_at IS NULL OR type != 'text'")
	if beforeID != nil {
		q = q.Where("id < ?", *beforeID)
	}
	if len(types) > 0 {
		q = q.Where("type IN ?", types)
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

// GetRepliedMessage возвращает краткие данные о сообщении для отображения цитаты.
type RepliedMessageRow struct {
	ID             uint
	SenderID       uint
	SenderUsername string
	Content        string
	Type           string
}

func (r *MessageRepository) GetRepliedMessages(ids []uint) (map[uint]RepliedMessageRow, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	type row struct {
		ID             uint   `gorm:"column:id"`
		SenderID       uint   `gorm:"column:sender_id"`
		SenderUsername string `gorm:"column:sender_username"`
		Content        string `gorm:"column:content"`
		Type           string `gorm:"column:type"`
	}
	var rows []row
	err := r.DB.Raw(`
		SELECT m.id, m.sender_id, u.username AS sender_username, m.content, m.type
		FROM messages m
		JOIN users u ON u.id = m.sender_id
		WHERE m.id IN ?
	`, ids).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	result := make(map[uint]RepliedMessageRow, len(rows))
	for _, rw := range rows {
		result[rw.ID] = RepliedMessageRow{
			ID:             rw.ID,
			SenderID:       rw.SenderID,
			SenderUsername: rw.SenderUsername,
			Content:        rw.Content,
			Type:           rw.Type,
		}
	}
	return result, nil
}

// GetReactionsForMessages возвращает реакции для набора сообщений.
func (r *MessageRepository) GetReactionsForMessages(messageIDs []uint, myUserID uint) (map[uint][]model.MessageReaction, error) {
	if len(messageIDs) == 0 {
		return nil, nil
	}
	var reactions []model.MessageReaction
	err := r.DB.Where("message_id IN ?", messageIDs).Find(&reactions).Error
	if err != nil {
		return nil, err
	}
	result := make(map[uint][]model.MessageReaction)
	for _, rc := range reactions {
		result[rc.MessageID] = append(result[rc.MessageID], rc)
	}
	return result, nil
}

// SaveMessage сохраняет сообщение и обновляет денормализованные поля чата в одной транзакции.
func (r *MessageRepository) SaveMessage(
	chatID, senderID uint,
	content, msgType string,
	fileName *string,
	fileSize *int64,
	caption *string,
	replyToID *uint,
	forwardedFromID *uint,
	forwardedFromUsername *string,
) (model.Message, error) {
	msg := model.Message{
		ChatID:                chatID,
		SenderID:              senderID,
		Content:               content,
		Type:                  msgType,
		FileName:              fileName,
		FileSize:              fileSize,
		Caption:               caption,
		ReplyToID:             replyToID,
		ForwardedFromID:       forwardedFromID,
		ForwardedFromUsername: forwardedFromUsername,
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

// EditMessage обновляет содержимое сообщения. Только автор может редактировать.
func (r *MessageRepository) EditMessage(msgID, senderID uint, content string) (model.Message, error) {
	now := time.Now()
	result := r.DB.Model(&model.Message{}).
		Where("id = ? AND sender_id = ? AND deleted_at IS NULL", msgID, senderID).
		Updates(map[string]any{
			"content":   content,
			"edited_at": now,
		})
	if result.Error != nil {
		return model.Message{}, result.Error
	}
	if result.RowsAffected == 0 {
		return model.Message{}, fmt.Errorf("message not found or access denied")
	}
	var msg model.Message
	return msg, r.DB.First(&msg, msgID).Error
}

// DeleteMessage выполняет soft-delete сообщения. Только автор или admin чата может удалять.
func (r *MessageRepository) DeleteMessage(msgID, requestUserID uint) (uint, error) {
	var msg model.Message
	if err := r.DB.First(&msg, "id = ? AND deleted_at IS NULL", msgID).Error; err != nil {
		return 0, fmt.Errorf("message not found")
	}

	isOwner := msg.SenderID == requestUserID
	if !isOwner {
		// Проверяем, является ли пользователь admin-ом чата
		var role string
		r.DB.Table("chat_members").
			Select("role").
			Where("chat_id = ? AND user_id = ?", msg.ChatID, requestUserID).
			Scan(&role)
		if role != "admin" {
			return 0, fmt.Errorf("access denied")
		}
	}

	if err := r.DB.Model(&msg).Updates(map[string]any{
		"deleted_at": time.Now(),
		"content":    "",
	}).Error; err != nil {
		return 0, err
	}
	return msg.ChatID, nil
}

// ToggleReaction добавляет реакцию или удаляет её, если тот же emoji уже стоит.
func (r *MessageRepository) ToggleReaction(msgID, userID uint, emoji string) error {
	var existing model.MessageReaction
	err := r.DB.Where("message_id = ? AND user_id = ?", msgID, userID).First(&existing).Error
	if err == nil {
		if existing.Emoji == emoji {
			// Тот же emoji — убрать
			return r.DB.Where("message_id = ? AND user_id = ?", msgID, userID).
				Delete(&model.MessageReaction{}).Error
		}
		// Другой emoji — обновить
		return r.DB.Model(&existing).Update("emoji", emoji).Error
	}
	// Новая реакция
	return r.DB.Create(&model.MessageReaction{
		MessageID: msgID,
		UserID:    userID,
		Emoji:     emoji,
	}).Error
}

// GetMessageReactions возвращает все реакции на одно сообщение.
func (r *MessageRepository) GetMessageReactions(msgID uint) ([]model.MessageReaction, error) {
	var reactions []model.MessageReaction
	return reactions, r.DB.Where("message_id = ?", msgID).Find(&reactions).Error
}

// SearchMessages ищет сообщения по тексту в чате.
func (r *MessageRepository) SearchMessages(chatID uint, query string, limit int, beforeID *uint) ([]model.Message, error) {
	q := r.DB.Where("chat_id = ? AND deleted_at IS NULL AND content ILIKE ?", chatID, "%"+query+"%")
	if beforeID != nil {
		q = q.Where("id < ?", *beforeID)
	}
	var messages []model.Message
	err := q.Order("id DESC").Limit(limit).Find(&messages).Error
	if err != nil {
		return nil, err
	}
	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}
	return messages, nil
}

// GetMessageChatID возвращает chat_id сообщения — нужен для broadcast после pin.
func (r *MessageRepository) GetMessageChatID(msgID uint) (uint, error) {
	var chatID uint
	err := r.DB.Table("messages").Select("chat_id").Where("id = ?", msgID).Scan(&chatID).Error
	if chatID == 0 {
		return 0, fmt.Errorf("message %d not found", msgID)
	}
	return chatID, err
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
