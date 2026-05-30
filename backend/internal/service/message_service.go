package service

import (
	dto "cove/internal/DTO"
	"cove/internal/model"
	"cove/internal/repository"
	"fmt"
)

type MessageService struct {
	repo *repository.MessageRepository
}

func NewMessageService(repo *repository.MessageRepository) *MessageService {
	return &MessageService{repo: repo}
}

func (s *MessageService) GetMessages(chatID uint, beforeID *uint, limit int, types []string) ([]model.Message, error) {
	return s.repo.GetMessages(chatID, beforeID, limit, types)
}

func (s *MessageService) SendMessage(
	chatID, senderID uint,
	content, msgType string,
	fileName *string,
	fileSize *int64,
	caption *string,
	replyToID *uint,
	forwardedFromID *uint,
	forwardedFromUsername *string,
) (model.Message, error) {
	if msgType == "" {
		msgType = "text"
	}
	msg, err := s.repo.SaveMessage(chatID, senderID, content, msgType, fileName, fileSize, caption, replyToID, forwardedFromID, forwardedFromUsername)
	if err != nil {
		return model.Message{}, fmt.Errorf("save message: %w", err)
	}
	return msg, nil
}

// EnrichMessages добавляет reply_to и reactions к списку MessageDTO.
func (s *MessageService) EnrichMessages(messages []model.Message, myUserID uint) ([]dto.MessageDTO, error) {
	dtos := make([]dto.MessageDTO, len(messages))
	for i, m := range messages {
		dtos[i] = dto.ToMessageDTO(m)
	}

	// Собираем reply_to_id для одного запроса
	var replyIDs []uint
	for _, m := range messages {
		if m.ReplyToID != nil {
			replyIDs = append(replyIDs, *m.ReplyToID)
		}
	}
	if len(replyIDs) > 0 {
		replied, err := s.repo.GetRepliedMessages(replyIDs)
		if err == nil {
			for i, m := range messages {
				if m.ReplyToID != nil {
					if rw, ok := replied[*m.ReplyToID]; ok {
						dtos[i].ReplyTo = &dto.RepliedMessageDTO{
							ID:             rw.ID,
							SenderID:       rw.SenderID,
							SenderUsername: rw.SenderUsername,
							Content:        rw.Content,
							Type:           rw.Type,
						}
					}
				}
			}
		}
	}

	// Реакции
	msgIDs := make([]uint, len(messages))
	for i, m := range messages {
		msgIDs[i] = m.ID
	}
	reactions, err := s.repo.GetReactionsForMessages(msgIDs, myUserID)
	if err == nil && len(reactions) > 0 {
		for i, m := range messages {
			raw := reactions[m.ID]
			if len(raw) == 0 {
				continue
			}
			groups := aggregateReactions(raw, myUserID)
			dtos[i].Reactions = groups
		}
	}

	return dtos, nil
}

func aggregateReactions(reactions []model.MessageReaction, myUserID uint) []dto.ReactionGroupDTO {
	counts := make(map[string]int)
	mine := make(map[string]bool)
	for _, r := range reactions {
		counts[r.Emoji]++
		if r.UserID == myUserID {
			mine[r.Emoji] = true
		}
	}
	result := make([]dto.ReactionGroupDTO, 0, len(counts))
	for emoji, count := range counts {
		result = append(result, dto.ReactionGroupDTO{
			Emoji:   emoji,
			Count:   count,
			HasMine: mine[emoji],
		})
	}
	return result
}

func (s *MessageService) EditMessage(msgID, senderID uint, content string) (model.Message, error) {
	return s.repo.EditMessage(msgID, senderID, content)
}

func (s *MessageService) DeleteMessage(msgID, requestUserID uint) (uint, error) {
	return s.repo.DeleteMessage(msgID, requestUserID)
}

func (s *MessageService) ToggleReaction(msgID, userID uint, emoji string) ([]model.MessageReaction, error) {
	if err := s.repo.ToggleReaction(msgID, userID, emoji); err != nil {
		return nil, fmt.Errorf("toggle reaction: %w", err)
	}
	return s.repo.GetMessageReactions(msgID)
}

func (s *MessageService) SearchMessages(chatID uint, query string, limit int, beforeID *uint) ([]model.Message, error) {
	if query == "" {
		return nil, fmt.Errorf("query is empty")
	}
	return s.repo.SearchMessages(chatID, query, limit, beforeID)
}

func (s *MessageService) IsChatMember(chatID, userID uint) (bool, error) {
	return s.repo.IsChatMember(chatID, userID)
}

func (s *MessageService) GetPartnerID(chatID, senderID uint) (uint, error) {
	return s.repo.GetPartnerID(chatID, senderID)
}

func (s *MessageService) GetChatMemberIDs(chatID uint) ([]uint, error) {
	return s.repo.GetChatMemberIDs(chatID)
}

func (s *MessageService) IsDMChat(chatID uint) (bool, error) {
	return s.repo.IsDMChat(chatID)
}

// MarkDelivered обновляет курсор доставки и возвращает senderID для уведомления.
func (s *MessageService) MarkDelivered(chatID, userID, messageID uint) (uint, error) {
	if err := s.repo.UpsertDeliveredCursor(chatID, userID, messageID); err != nil {
		return 0, fmt.Errorf("upsert delivered cursor: %w", err)
	}
	return s.repo.GetMessageSenderID(messageID)
}

// MarkRead обновляет курсор прочтения (и доставки) и возвращает senderID для уведомления.
func (s *MessageService) MarkRead(chatID, userID, messageID uint) (uint, error) {
	if err := s.repo.UpsertReadCursor(chatID, userID, messageID); err != nil {
		return 0, fmt.Errorf("upsert read cursor: %w", err)
	}
	return s.repo.GetMessageSenderID(messageID)
}

// GetPartnerCursor возвращает курсор партнёра в DM для отображения статуса сообщений.
func (s *MessageService) GetPartnerCursor(chatID, myUserID uint) (*model.ChatReadCursor, error) {
	return s.repo.GetPartnerCursor(chatID, myUserID)
}
