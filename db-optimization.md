# Cove — Оптимизация схемы БД

**Дата:** 2026-05-03  
**Цель:** Заложить фундамент для работы при 100 000+ DAU, пока таблицы пустые и изменения дешёвые.

---

## Проблемы и решения

### 1. Бесполезный индекс на `friendships` (КРИТИЧНО)

**Проблема:** `idx_friendships_status ON friendships(status)` — индекс по колонке с 3 значениями. PostgreSQL его не использует, зато нужных индексов нет.

```sql
-- Запрос GetPendingRequests:
WHERE friend_id = ? AND status = 'pending'
-- → full scan, т.к. нет индекса по friend_id
```

**Решение:**
```sql
-- Migration 003
DROP INDEX idx_friendships_status;
CREATE INDEX idx_friendships_friend_status ON friendships(friend_id, status);
CREATE INDEX idx_friendships_user_status   ON friendships(user_id,   status);
```

---

### 2. `GetFriends` использует `OR` — плохо масштабируется

**Проблема:**
```sql
WHERE (user_id = ? OR friend_id = ?) AND status = 'accepted'
-- OR по двум разным колонкам → Bitmap Index Scan + OR, медленно на больших таблицах
```

**Решение:** При принятии заявки создавать **две симметричные строки** в одной транзакции:
- `(user_id=A, friend_id=B, status=accepted)` — уже есть
- `(user_id=B, friend_id=A, status=accepted)` — добавляется при accept

`GetFriends` упрощается до:
```sql
WHERE user_id = ? AND status = 'accepted'
-- → Index Scan по idx_friendships_user_status, O(log n)
```

При удалении дружбы — удалять обе строки.

**Изменение в коде:** `friendship_repository.go` → `RespondToFriendRequest` при `accepted` вставляет обратную запись в той же транзакции.

---

### 3. `read_status` растёт как O(messages × users) (КРИТИЧНО)

**Проблема:**
```sql
read_status(message_id, user_id, read_at)
-- 1000 users × 10 000 messages = 10 000 000 строк
```

**Решение:** Курсор на уровне чата вместо строки на каждое сообщение:
```sql
-- Migration 006: удалить read_status, создать:
chat_read_cursor (
  chat_id              INTEGER REFERENCES chats(id),
  user_id              INTEGER REFERENCES users(id),
  last_read_message_id INTEGER REFERENCES messages(id),
  PRIMARY KEY (chat_id, user_id)
)
```

| Операция | Было | Стало |
|---|---|---|
| Отметить прочитанным | INSERT строки | UPSERT одной строки |
| Кол-во непрочитанных | COUNT по read_status | COUNT messages WHERE id > last_read_message_id |
| Рост таблицы | O(messages × users) | O(chats × users) |

---

### 4. Нет индекса для пагинации сообщений (КРИТИЧНО)

**Проблема:**
```sql
WHERE chat_id = ? AND id < ?before ORDER BY id DESC LIMIT 50
-- Нет составного индекса → full scan по messages
```

**Решение:**
```sql
-- Migration 004
CREATE INDEX idx_messages_chat_id ON messages(chat_id, id DESC);
```

---

### 5. `GET /chat/` — дорогая агрегация без денормализации

**Проблема:** Получить превью последнего сообщения для каждого чата:
```sql
-- Subquery per row — O(n × log m)
WHERE m.id = (SELECT MAX(id) FROM messages WHERE chat_id = c.id)
```

**Решение:** Денормализовать в таблицу `chats`:
```sql
-- Migration 005
ALTER TABLE chats
  ADD COLUMN last_message_id      INTEGER REFERENCES messages(id),
  ADD COLUMN last_message_at       TIMESTAMPTZ,
  ADD COLUMN last_message_content  TEXT;
```

Обновлять при каждой отправке сообщения в `message_repository.go`. `GET /chat/` становится одним JOIN.

---

### 6. Нет индекса `chat_members(user_id)`

**Проблема:**
```sql
-- Найти все чаты пользователя:
WHERE user_id = ?  -- full scan без индекса
```

**Решение:**
```sql
-- Migration 004
CREATE INDEX idx_chat_members_user_id ON chat_members(user_id);
```

---

### 7. Connection pool не настроен

**Проблема:** GORM по умолчанию создаёт неограниченное число соединений → PostgreSQL перегружается при 100+ одновременных запросах.

**Решение в `cmd/main.go`:**
```go
sqlDB, _ := db.DB()
sqlDB.SetMaxOpenConns(25)
sqlDB.SetMaxIdleConns(5)
sqlDB.SetConnMaxLifetime(5 * time.Minute)
```

---

## План миграций

| № | Файл | Действие |
|---|---|---|
| 003 | `003_fix_friendship_indexes.up.sql` | Удалить `idx_friendships_status`, добавить составные индексы |
| 004 | `004_add_chat_indexes.up.sql` | `idx_messages_chat_id`, `idx_chat_members_user_id` |
| 005 | `005_add_chat_last_message.up.sql` | Три колонки в `chats` для денормализации |
| 006 | `006_replace_read_status.up.sql` | Удалить `read_status`, создать `chat_read_cursor` |

## Изменения в Go-коде

| Файл | Что меняется |
|---|---|
| `internal/repository/friendship_repository.go` | `RespondToFriendRequest`: INSERT обратной записи в транзакции при `accepted`; `GetFriends` — упрощённый запрос |
| `internal/repository/chat_repository.go` (новый) | Запросы для чатов, обновление `last_message_*` |
| `internal/repository/message_repository.go` (новый) | Cursor-based пагинация |
| `internal/model/chat.go` (новый) | Структуры `Chat`, `ChatMember`, `Message`, `ChatReadCursor` |
| `cmd/main.go` | Настройка connection pool |

---

## Верификация после реализации

1. `go build ./...` — проект собирается
2. `docker-compose up` + миграции — все таблицы создаются
3. Принять заявку в друзья → в `friendships` должны появиться **две** строки с `status=accepted`
4. `EXPLAIN ANALYZE` на ключевых запросах — убедиться в `Index Scan`, а не `Seq Scan`
5. `GetFriends` возвращает список без дублей
