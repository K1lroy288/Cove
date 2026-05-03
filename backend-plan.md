# Cove — Backend Plan (актуальный)

**Base URL:** `http://localhost:3425`  
**Формат данных:** JSON  
**Версия:** 2.0 (2026-05-03) — с учётом db-optimization.md и ROADMAP.md

---

## Общие соглашения

### Аутентификация
Все защищённые эндпоинты требуют заголовок:
```
Authorization: Bearer <access_token>
```
Токен выдаётся при логине (`POST /auth/login`). При отсутствии или невалидности — `401 Unauthorized`.

### Формат ошибок
```json
{ "message": "Описание ошибки" }
```

### HTTP-статусы
| Код | Когда |
|---|---|
| `200` | Успешный GET / PATCH / POST без нового ресурса |
| `201` | Успешное создание ресурса |
| `400` | Невалидный JSON, отсутствующие поля, бизнес-ошибка |
| `401` | Отсутствует или невалидный JWT |
| `403` | Токен валидный, но нет прав |
| `404` | Ресурс не найден |
| `409` | Конфликт — ресурс уже существует |
| `410` | Ресурс существовал, но больше недоступен |
| `429` | Rate limit превышен |
| `500` | Внутренняя ошибка сервера |

---

## Архитектура

### Сейчас (Фаза 1)
```
Flutter ──── HTTP/WS ──── Go (1 инстанс) ──── PostgreSQL
```

### Цель (Фаза 2, 100k DAU)
```
                    ┌──────────────────────────────────┐
Flutter ──── HTTPS ─┤  Nginx (SSL termination,         │
Flutter ────  WSS ──┤         sticky sessions для WS)  │
                    └──────┬───────────────┬────────────┘
                           │               │
                    ┌──────▼──────┐  ┌─────▼──────┐
                    │  Go App 1   │  │  Go App 2  │  (горизонтально)
                    │  (Hub)      │  │  (Hub)     │
                    └──────┬──────┘  └─────┬──────┘
                           │               │
                    ┌──────▼───────────────▼──────┐
                    │            Redis             │
                    │  • Pub/Sub (distributed Hub) │
                    │  • Presence (online status)  │
                    │  • Rate limiting             │
                    └──────┬──────────────┬────────┘
                           │              │
              ┌────────────▼──┐  ┌────────▼──────┐
              │ PostgreSQL    │  │  PostgreSQL   │
              │  (Primary)    │  │  (Replica)    │
              └───────────────┘  └───────────────┘
```

**Принципы:**
- Go-инстансы stateless — состояние только в Redis и PostgreSQL
- WebSocket Hub в Фазе 1 — in-memory map; в Фазе 2 — Redis Pub/Sub
- Presence (онлайн-статус) — Redis SET с TTL, не PostgreSQL
- Read-heavy запросы (история) — идут на реплику

---

## Файловая структура Go-проекта (целевая)

```
backend/
├── cmd/
│   └── main.go                          — точка входа, роутинг, DI
├── internal/
│   ├── config/
│   │   └── config.go                    — конфиг из env
│   ├── db/
│   │   ├── migrator.go
│   │   └── migration/
│   │       ├── 001_create_users.up.sql
│   │       ├── 002_create_friendships.up.sql
│   │       ├── 003_fix_friendship_indexes.up.sql    ← новая
│   │       ├── 004_create_chats.up.sql              ← новая
│   │       ├── 005_create_messages.up.sql           ← новая
│   │       ├── 006_create_voice_rooms.up.sql        ← новая
│   │       └── 007_create_reactions.up.sql          ← новая
│   ├── hub/
│   │   ├── hub.go                       — Hub struct, Register/Unregister/Run  ← новая
│   │   ├── client.go                    — Client struct, readPump/writePump     ← новая
│   │   └── message.go                   — WsMessage{Type, Payload}              ← новая
│   ├── model/
│   │   ├── user.go
│   │   ├── friendship.go
│   │   ├── chat.go                      — Chat, ChatMember, ChatReadCursor      ← новая
│   │   ├── message.go                   — Message                               ← новая
│   │   ├── voice_room.go                — VoiceRoom, RoomMember                 ← новая
│   │   ├── reaction.go                  — Reaction                              ← новая
│   │   └── custom_claims.go
│   ├── DTO/
│   │   ├── user.go
│   │   ├── friendship.go
│   │   ├── chat.go                      ← новая
│   │   ├── message.go                   ← новая
│   │   └── voice_room.go                ← новая
│   ├── repository/
│   │   ├── user_repository.go
│   │   ├── friendship_repository.go     — обновить (симм. записи)
│   │   ├── chat_repository.go           ← новая
│   │   ├── message_repository.go        ← новая
│   │   └── voice_room_repository.go     ← новая
│   ├── service/
│   │   ├── user_service.go
│   │   ├── friendship_service.go        — обновить
│   │   ├── chat_service.go              ← новая
│   │   ├── message_service.go           ← новая
│   │   └── voice_room_service.go        ← новая
│   ├── handler/
│   │   ├── user_handler.go
│   │   ├── friendship_handler.go        — обновить
│   │   ├── chat_handler.go              ← новая
│   │   ├── message_handler.go           ← новая
│   │   ├── voice_room_handler.go        ← новая
│   │   └── ws_handler.go                ← новая
│   ├── middleware/
│   │   ├── auth.go
│   │   └── rate_limit.go                ← новая (Фаза 2)
│   └── utils/
│       └── generate_jwt.go
└── deployments/
    ├── docker-compose.yml               — обновить (Redis, MinIO, LiveKit)
    └── Dockerfile
```

---

## Схема базы данных (целевая, оптимизированная)

### Таблицы

```sql
-- ──────────────────────────────────────────────────────────────────────────────
-- Уже существует (migrations 001–002)
-- ──────────────────────────────────────────────────────────────────────────────

users (
  id            SERIAL PRIMARY KEY,
  username      VARCHAR(100) UNIQUE NOT NULL,
  password_hash BYTEA NOT NULL,
  settings      JSONB,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  deleted_at    TIMESTAMPTZ                   -- мягкое удаление
)

friendships (
  user_id    INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id  INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status     friendship_status NOT NULL DEFAULT 'pending',  -- ENUM: pending|accepted|blocked
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, friend_id),
  CONSTRAINT check_not_self CHECK (user_id <> friend_id)
)
-- Важно: при принятии заявки создаются ДВЕ строки:
--   (A→B, accepted) + (B→A, accepted)
-- При удалении дружбы — удаляются обе строки.
-- Это позволяет GetFriends делать WHERE user_id=? AND status='accepted'
-- без OR-условий, которые не используют индекс.

-- ──────────────────────────────────────────────────────────────────────────────
-- Migration 003: исправить индексы friendships
-- ──────────────────────────────────────────────────────────────────────────────
-- DROP INDEX idx_friendships_status;  ← бесполезен (3 значения, никогда не используется)
-- Вместо него:
-- idx_friendships_friend_status ON friendships(friend_id, status)  ← GetPendingRequests
-- idx_friendships_user_status   ON friendships(user_id,   status)  ← GetFriends

-- ──────────────────────────────────────────────────────────────────────────────
-- Migration 004: чаты
-- ──────────────────────────────────────────────────────────────────────────────

chats (
  id                    SERIAL PRIMARY KEY,
  last_message_id       INT REFERENCES messages(id),   -- денормализация для GET /chat/
  last_message_at       TIMESTAMPTZ,
  last_message_content  TEXT,
  created_at            TIMESTAMPTZ DEFAULT NOW()
)
-- Поля last_message_* обновляются при каждой отправке сообщения.
-- Благодаря этому GET /chat/ — простой JOIN без субзапросов.

chat_members (
  chat_id    INT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id    INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (chat_id, user_id)
)

-- ──────────────────────────────────────────────────────────────────────────────
-- Migration 005: сообщения
-- ──────────────────────────────────────────────────────────────────────────────

messages (
  id          SERIAL PRIMARY KEY,
  chat_id     INT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  sender_id   INT NOT NULL REFERENCES users(id),
  content     TEXT NOT NULL,
  type        VARCHAR(20) NOT NULL DEFAULT 'text',   -- text|image|voice|file
  reply_to_id INT REFERENCES messages(id),           -- Фаза 2: ответ/цитата
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  edited_at   TIMESTAMPTZ,
  deleted_at  TIMESTAMPTZ                            -- мягкое удаление
)

chat_read_cursor (
  chat_id              INT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id              INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_read_message_id INT REFERENCES messages(id),
  updated_at           TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (chat_id, user_id)
)
-- Заменяет read_status(message_id, user_id).
-- read_status рос как O(messages × users) → миллиарды строк.
-- chat_read_cursor растёт как O(chats × users) — в тысячи раз меньше.
-- Непрочитанных: SELECT COUNT(*) FROM messages WHERE chat_id=? AND id > last_read_message_id

-- ──────────────────────────────────────────────────────────────────────────────
-- Migration 006: голосовые комнаты (Фаза 4)
-- ──────────────────────────────────────────────────────────────────────────────

voice_rooms (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  created_by INT NOT NULL REFERENCES users(id),
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
)

room_members (
  room_id   INT NOT NULL REFERENCES voice_rooms(id) ON DELETE CASCADE,
  user_id   INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  is_muted  BOOLEAN NOT NULL DEFAULT FALSE,
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (room_id, user_id)
)

-- ──────────────────────────────────────────────────────────────────────────────
-- Migration 007: реакции (Фаза 2)
-- ──────────────────────────────────────────────────────────────────────────────

reactions (
  message_id INT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id    INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji      VARCHAR(10) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id, emoji)
)
```

### Индексы (все)

```sql
-- users
CREATE INDEX idx_users_username ON users(username);           -- уже есть (migration 001)

-- friendships
-- DROP INDEX idx_friendships_status;                         -- migration 003: убрать
CREATE INDEX idx_friendships_friend_status ON friendships(friend_id, status);  -- GetPendingRequests
CREATE INDEX idx_friendships_user_status   ON friendships(user_id,   status);  -- GetFriends

-- chat_members
CREATE INDEX idx_chat_members_user_id ON chat_members(user_id);  -- найти чаты пользователя

-- messages
CREATE INDEX idx_messages_chat_id ON messages(chat_id, id DESC);  -- cursor-based пагинация

-- room_members (FK индексы создаются PostgreSQL автоматически)
```

---

## Фаза 1 — Базовый мессенджер

---

### 1. Auth

#### `POST /auth/register` ✅

**Auth:** не требуется

**Body:**
```json
{ "username": "alice", "password": "secret123" }
```

**Ответы:**
| Код | Условие |
|---|---|
| `201` | Пользователь создан |
| `400` | Невалидный JSON / пустые поля |
| `400` | Username уже занят |

---

#### `POST /auth/login` ✅

**Auth:** не требуется

**Body:**
```json
{ "username": "alice", "password": "secret123" }
```

**Ответ `200`:**
```json
{
  "token": "eyJhbGci...",
  "userId": 42,
  "username": "alice"
}
```

**Ошибки:**
| Код | Условие |
|---|---|
| `401` | Username не найден или неверный пароль |

---

#### `POST /auth/refresh` ❌ (Фаза 5)

**Auth:** не требуется

**Body:**
```json
{ "refresh_token": "eyJhbGci..." }
```

**Ответ `200`:**
```json
{
  "token": "eyJhbGci...",
  "refresh_token": "eyJhbGci..."
}
```

**Логика:**
1. Проверить refresh token (подпись, TTL, не в Redis-блэклисте)
2. Выдать новый access token (15 мин) + новый refresh token (30 дней)
3. Старый refresh token записать в Redis-блэклист (TTL = оставшееся время жизни)

**Ошибки:**
| Код | Условие |
|---|---|
| `401` | Невалидный или истёкший refresh token |

---

### 2. User

#### `GET /user/search?q=<query>` ✅

**Auth:** не требуется

Поиск по exact username, затем (если q — число) по ID.

**Ответ `200`:**
```json
{ "id": 42, "username": "alice" }
```

**Ошибки:** `400` (нет q), `404` (не найден)

---

#### `GET /user/username/:username` ✅

**Auth:** не требуется  
> Маршрут должен быть зарегистрирован **до** `/:id`, иначе Gin захватит его.

**Ответ `200`:** `{ "id": 42, "username": "alice" }`

---

#### `GET /user/:id` ✅

**Auth:** не требуется

**Ответ `200`:** `{ "id": 42, "username": "alice" }`

**Ошибки:** `400` (id не число), `404`

---

#### `GET /user/:id/presence` ❌ (Фаза 2)

**Auth:** требуется (JWT)

**Логика:** `GET presence:{id}` из Redis. Если ключ есть — online, нет — offline.

**Ответ `200`:**
```json
{ "user_id": 42, "status": "online" }
```
Допустимые значения `status`: `"online"`, `"offline"`

---

### 3. Friendship

#### `POST /friendship/` ✅

**Auth:** требуется (JWT)

**Body:**
```json
{ "user_id": 1, "friend_id": 2, "status": "pending" }
```

**Логика:**
1. Проверить `user_id != friend_id`
2. `INSERT INTO friendships (user_id, friend_id, status) VALUES (?, ?, 'pending')`
3. Отправить WS-событие `friend_request` пользователю `friend_id` (если он онлайн)

**Ответы:** `201` (создана), `400` (самодобавление / дублирует)

---

#### `GET /friendship/pending?user_id=<id>` ✅

**Auth:** требуется (JWT)

**Логика:** `WHERE friend_id = ? AND status = 'pending'` — использует `idx_friendships_friend_status`

**Ответ `200`:**
```json
[
  { "user_id": 7, "username": "bob" },
  { "user_id": 15, "username": "charlie" }
]
```

---

#### `GET /friendship/pending/count?user_id=<id>` ✅

**Auth:** требуется (JWT)

**Ответ `200`:** `{ "count": 3 }`

---

#### `PATCH /friendship/:user_id/status` ❌ Sprint 1

**Auth:** требуется (JWT — получатель заявки)  
**Path:** `:user_id` — ID отправителя заявки

**Body:**
```json
{ "status": "accepted" }
```
Допустимые значения: `"accepted"`, `"declined"`

**Логика при `accepted`:**
```
BEGIN TRANSACTION
  UPDATE friendships SET status='accepted'
    WHERE user_id=:user_id AND friend_id=<из JWT> AND status='pending'
  INSERT INTO friendships (user_id, friend_id, status)
    VALUES (<из JWT>, :user_id, 'accepted')          -- симметричная запись
COMMIT
```
После транзакции — автоматически создать чат (`POST /chat/` логика).

**Логика при `declined`:**
```
DELETE FROM friendships
  WHERE user_id=:user_id AND friend_id=<из JWT> AND status='pending'
```

**Ответ `200`:**
```json
{ "message": "Заявка принята" }
```
или
```json
{ "message": "Заявка отклонена" }
```

**Ошибки:**
| Код | Условие |
|---|---|
| `400` | Недопустимый статус |
| `404` | Заявка не найдена |

---

#### `GET /friendship/friends` ❌ Sprint 1

**Auth:** требуется (JWT — берёт user_id из токена)

**Логика:** `WHERE user_id=<из JWT> AND status='accepted'` — использует `idx_friendships_user_status`

> **Нет query параметра** `user_id` — берётся из JWT. Это безопасно и соответствует принципу "пользователь видит только своих друзей".

**Ответ `200`:**
```json
[
  { "id": 7, "username": "bob" },
  { "id": 15, "username": "charlie" }
]
```

---

### 4. Chat

#### `POST /chat/` ❌ Sprint 1

**Auth:** требуется (JWT)

**Body:**
```json
{ "friend_id": 7 }
```

**Логика:**
1. Проверить, что `friend_id` — друг текущего пользователя (`status='accepted'`)
2. Найти существующий DM-чат между ними:
   ```sql
   SELECT c.id FROM chats c
   JOIN chat_members cm1 ON cm1.chat_id = c.id AND cm1.user_id = <me>
   JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id = <friend_id>
   LIMIT 1
   ```
3. Если есть — вернуть `200` с существующим
4. Если нет — создать чат + добавить обоих в `chat_members`, вернуть `201`

**Ответ `201` / `200`:**
```json
{
  "id": 101,
  "partner_id": 7,
  "partner_name": "bob",
  "last_message": null,
  "last_message_at": null,
  "unread_count": 0
}
```

**Ошибки:**
| Код | Условие |
|---|---|
| `403` | `friend_id` не является другом |

---

#### `GET /chat/` ❌ Sprint 1

**Auth:** требуется (JWT — берёт user_id из токена)

**Логика:**
```sql
SELECT
  c.id,
  u.id          AS partner_id,
  u.username    AS partner_name,
  c.last_message_content AS last_message,
  c.last_message_at,
  COALESCE(
    (SELECT COUNT(*) FROM messages m
     WHERE m.chat_id = c.id
       AND m.id > COALESCE(crc.last_read_message_id, 0)
       AND m.deleted_at IS NULL),
    0
  )             AS unread_count
FROM chats c
JOIN chat_members cm  ON cm.chat_id = c.id AND cm.user_id = <me>
JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id != <me>
JOIN users u          ON u.id = cm2.user_id AND u.deleted_at IS NULL
LEFT JOIN chat_read_cursor crc ON crc.chat_id = c.id AND crc.user_id = <me>
ORDER BY c.last_message_at DESC NULLS LAST
```

`last_message_*` колонки в `chats` устраняют субзапрос на каждый чат.

**Ответ `200`:**
```json
[
  {
    "id": 101,
    "partner_id": 7,
    "partner_name": "bob",
    "last_message": "Привет!",
    "last_message_at": "2026-05-02T14:30:00Z",
    "unread_count": 3
  }
]
```

---

### 5. Messages

#### `GET /chat/:id/messages` ❌ Sprint 3

**Auth:** требуется (JWT)  
**Path:** `id` — ID чата  
**Query:**
| Параметр | Тип | Default | Описание |
|---|---|---|---|
| `limit` | number | `50` | Кол-во сообщений |
| `before` | number | — | Вернуть сообщения с `id < before` (подгрузка истории вверх) |

**Логика:**
```sql
WHERE chat_id = ? [AND id < ?before] AND deleted_at IS NULL
ORDER BY id DESC
LIMIT ?limit
-- Использует idx_messages_chat_id → Index Range Scan
```
Результат реверсировать перед отдачей (хронологический порядок).

**Ответ `200`:**
```json
[
  {
    "id": 1001,
    "chat_id": 101,
    "sender_id": 42,
    "content": "Привет!",
    "type": "text",
    "reply_to_id": null,
    "created_at": "2026-05-02T14:25:00Z",
    "edited_at": null
  }
]
```

**Ошибки:**
| Код | Условие |
|---|---|
| `403` | Текущий пользователь не участник чата |
| `404` | Чат не найден |

---

#### `POST /chat/:id/messages` ❌ Sprint 3

**Auth:** требуется (JWT — берёт sender_id из токена)

**Body:**
```json
{ "content": "Привет!", "type": "text" }
```
Поле `type`: `"text"` | `"image"` | `"voice"` | `"file"` (default: `"text"`)

**Логика:**
1. Проверить, что текущий пользователь — участник чата
2. `INSERT INTO messages`
3. `UPDATE chats SET last_message_id=?, last_message_at=?, last_message_content=?`
4. `UPSERT chat_read_cursor` — обновить курсор прочтения отправителя
5. Broadcast WS-событие `message` всем участникам чата через Hub

**Ответ `201`:**
```json
{
  "id": 1003,
  "chat_id": 101,
  "sender_id": 42,
  "content": "Привет!",
  "type": "text",
  "reply_to_id": null,
  "created_at": "2026-05-02T14:30:00Z",
  "edited_at": null
}
```

---

### 6. WebSocket

#### `GET /ws?token=<jwt>` ❌ Sprint 2

WebSocket upgrade. Токен передаётся в query-параметре (HTTP заголовки после upgrade недоступны).

**После подключения:**
1. Валидировать JWT из query
2. Привязать соединение к `user_id`
3. Зарегистрировать клиента в Hub
4. Установить `SETEX presence:{user_id} 60 "online"` (Фаза 2)
5. Запустить readPump + writePump goroutines

**При отключении:**
1. Удалить клиента из Hub
2. `DEL presence:{user_id}` (Фаза 2)
3. Broadcast `presence: offline` друзьям (Фаза 2)

**Ping/Pong:** сервер шлёт Ping каждые 30 сек, ждёт Pong 10 сек, иначе закрывает соединение.

---

#### Формат всех WS-сообщений

```json
{ "type": "<event_type>", "payload": { ... } }
```

---

#### События сервер → клиент

**`message`** — новое сообщение в чате
```json
{
  "type": "message",
  "payload": {
    "id": 1003,
    "chat_id": 101,
    "sender_id": 7,
    "content": "Привет!",
    "type": "text",
    "reply_to_id": null,
    "created_at": "2026-05-02T14:30:00Z"
  }
}
```

**`typing`** — пользователь печатает
```json
{
  "type": "typing",
  "payload": { "chat_id": 101, "user_id": 7, "is_typing": true }
}
```

**`read`** — сообщение прочитано
```json
{
  "type": "read",
  "payload": { "chat_id": 101, "last_read_message_id": 1003, "user_id": 7 }
}
```
> Используем `last_read_message_id`, а не `message_id` — соответствует `chat_read_cursor`.

**`presence`** — изменился статус онлайн
```json
{
  "type": "presence",
  "payload": { "user_id": 7, "status": "online" }
}
```
Допустимые значения `status`: `"online"`, `"offline"`

**`friend_request`** — новая заявка в друзья
```json
{
  "type": "friend_request",
  "payload": { "from_user_id": 7, "username": "bob" }
}
```

**`room_update`** — изменился состав голосовой комнаты
```json
{
  "type": "room_update",
  "payload": { "room_id": 1, "user_id": 99, "username": "alice", "action": "join" }
}
```
Допустимые значения `action`: `"join"`, `"leave"`

**`reaction`** — реакция на сообщение (Фаза 2)
```json
{
  "type": "reaction",
  "payload": { "message_id": 1001, "user_id": 7, "emoji": "👍", "action": "add" }
}
```
Допустимые значения `action`: `"add"`, `"remove"`

---

#### События клиент → сервер

**Typing indicator:**
```json
{ "type": "typing", "payload": { "chat_id": 101, "is_typing": true } }
```
Клиент шлёт при каждом нажатии клавиши (дебounce 1 сек на клиенте).

**Отметить прочитанным:**
```json
{ "type": "read", "payload": { "chat_id": 101, "message_id": 1003 } }
```
Сервер делает `UPSERT chat_read_cursor`, затем broadcast `read` участникам чата.

---

#### Hub — реализация (Go)

```go
// internal/hub/hub.go

type Hub struct {
    clients    map[uint]*Client  // userID → Client
    mu         sync.RWMutex
    broadcast  chan HubMessage
    register   chan *Client
    unregister chan *Client
}

type HubMessage struct {
    ToUserID uint
    Message  []byte
}

func (h *Hub) Run() {
    for {
        select {
        case client := <-h.register:
            h.mu.Lock()
            h.clients[client.UserID] = client
            h.mu.Unlock()
        case client := <-h.unregister:
            h.mu.Lock()
            delete(h.clients, client.UserID)
            h.mu.Unlock()
        case msg := <-h.broadcast:
            h.mu.RLock()
            if client, ok := h.clients[msg.ToUserID]; ok {
                client.send <- msg.Message
            }
            h.mu.RUnlock()
        }
    }
}
```

**Фаза 2 — Redis Pub/Sub:**  
При broadcast вместо прямой отправки → `redis.Publish("user:{userID}", message)`.  
Каждый инстанс Go подписан на `user:*` и пушит своим локальным клиентам.

---

## Фаза 2 — Реакции и присутствие

### `POST /message/:id/reaction` ❌ Sprint 6

**Auth:** требуется (JWT)

**Body:**
```json
{ "emoji": "👍" }
```

**Логика — toggle:**
```sql
-- Если реакция уже есть → DELETE (убрать)
-- Если нет → INSERT (добавить)
```
После изменения — broadcast WS-событие `reaction` участникам чата.

**Ответ `200`:**
```json
{ "action": "add", "emoji": "👍", "message_id": 1001 }
```

---

### Rate Limiting (middleware) ❌ Sprint 6

Redis-based token bucket на каждого пользователя/IP:

| Эндпоинт | Лимит |
|---|---|
| `POST /chat/:id/messages` | 60 сообщений / мин на user |
| `POST /auth/*` | 10 запросов / мин на IP |
| `POST /friendship/` | 20 заявок / час на user |

Ответ при превышении: `429 Too Many Requests`  
Заголовок: `Retry-After: <seconds>`

---

## Фаза 3 — Медиафайлы

### `POST /upload` ❌ Sprint 7

**Auth:** требуется (JWT)  
**Content-Type:** `multipart/form-data`

**Поля формы:**
| Поле | Описание |
|---|---|
| `file` | Файл (max 10 MB) |
| `type` | `"image"` \| `"voice"` \| `"file"` |

**Логика:**
1. Валидировать размер (≤ 10 MB) и MIME-type
2. Для `image`: сжать до max 1920px, JPEG 85%, создать thumbnail 200×200
3. Сохранить в MinIO (bucket `cove-media`)
4. Вернуть URL

**Ответ `201`:**
```json
{
  "url": "https://media.cove.app/cove-media/images/2026/05/abc123.jpg",
  "thumbnail_url": "https://media.cove.app/cove-media/thumbs/2026/05/abc123.jpg",
  "type": "image",
  "size": 245678
}
```

Клиент после загрузки вызывает `POST /chat/:id/messages` с `type="image"` и `content=<url>`.

---

## Фаза 4 — Голосовые комнаты

### `GET /voice-room/` ❌ Sprint 8

**Auth:** требуется (JWT)

**Ответ `200`:**
```json
[
  {
    "id": 1,
    "name": "Общая комната",
    "created_by": 42,
    "is_active": true,
    "members": [
      { "user_id": 42, "username": "alice", "is_muted": false },
      { "user_id": 7,  "username": "bob",   "is_muted": true }
    ]
  }
]
```

---

### `POST /voice-room/` ❌ Sprint 8

**Auth:** требуется (JWT)

**Body:**
```json
{ "name": "Вечерний чилл" }
```

**Логика:**
1. `INSERT INTO voice_rooms`
2. `INSERT INTO room_members` (создатель автоматически входит)
3. Выдать LiveKit token для создателя (ему нужно подключиться к SFU)

**Ответ `201`:**
```json
{
  "id": 2,
  "name": "Вечерний чилл",
  "created_by": 42,
  "is_active": true,
  "livekit_token": "eyJhbGci...",
  "members": [
    { "user_id": 42, "username": "alice", "is_muted": false }
  ]
}
```

---

### `POST /voice-room/:id/join` ❌ Sprint 8

**Auth:** требуется (JWT)

**Логика:**
1. Проверить, что комната активна (`is_active = true`)
2. `UPSERT room_members` (если уже внутри — не падать)
3. Выдать LiveKit token для участника
4. Broadcast WS-событие `room_update` всем участникам

**Ответ `200`:**
```json
{
  "id": 1,
  "name": "Общая комната",
  "livekit_token": "eyJhbGci...",
  "members": [
    { "user_id": 42, "username": "alice", "is_muted": false },
    { "user_id": 7,  "username": "bob",   "is_muted": false },
    { "user_id": 99, "username": "new_user", "is_muted": false }
  ]
}
```

**Ошибки:**
| Код | Условие |
|---|---|
| `404` | Комната не найдена |
| `410` | Комната неактивна (все вышли) |

---

### `POST /voice-room/:id/leave` ❌ Sprint 8

**Auth:** требуется (JWT)

**Логика:**
1. `DELETE FROM room_members WHERE room_id=? AND user_id=<из JWT>`
2. Если участников не осталось → `UPDATE voice_rooms SET is_active=false`
3. Broadcast WS-событие `room_update` оставшимся участникам

**Ответ `200`:**
```json
{ "message": "Вы покинули комнату" }
```

---

## Фаза 5 — Production-ready

### `GET /healthz` ❌

**Auth:** не требуется

**Логика:** проверить соединение с PostgreSQL (`db.Ping()`) и Redis.

**Ответ `200`:**
```json
{ "status": "ok", "postgres": "ok", "redis": "ok" }
```

**Ответ `503`:**
```json
{ "status": "degraded", "postgres": "ok", "redis": "error" }
```

---

### `GET /metrics` ❌ (Фаза 5)

Prometheus-совместимый формат. Метрики:
- `cove_http_requests_total` — RPS по эндпоинтам
- `cove_http_request_duration_seconds` — латентность
- `cove_ws_connections_active` — активные WebSocket соединения
- `cove_hub_broadcast_queue_length` — размер очереди Hub
- `cove_messages_sent_total` — всего отправлено сообщений

---

## Connection Pool (cmd/main.go)

```go
// Сразу после gorm.Open():
sqlDB, err := db.DB()
if err != nil {
    log.Fatalf("Failed to get sql.DB: %v", err)
}
sqlDB.SetMaxOpenConns(25)            // не перегружать PostgreSQL
sqlDB.SetMaxIdleConns(5)
sqlDB.SetConnMaxLifetime(5 * time.Minute)
```

---

## Сводная таблица эндпоинтов

| Метод | Path | Auth | Фаза | Статус |
|---|---|---|---|---|
| `POST` | `/auth/register` | ❌ | 1 | ✅ |
| `POST` | `/auth/login` | ❌ | 1 | ✅ |
| `POST` | `/auth/refresh` | ❌ | 5 | ❌ |
| `GET` | `/user/search?q=` | ❌ | 1 | ✅ |
| `GET` | `/user/username/:username` | ❌ | 1 | ✅ |
| `GET` | `/user/:id` | ❌ | 1 | ✅ |
| `GET` | `/user/:id/presence` | ✅ | 2 | ❌ |
| `POST` | `/friendship/` | ✅ | 1 | ✅ |
| `GET` | `/friendship/pending` | ✅ | 1 | ✅ |
| `GET` | `/friendship/pending/count` | ✅ | 1 | ✅ |
| `PATCH` | `/friendship/:user_id/status` | ✅ | 1 | ❌ Sprint 1 |
| `GET` | `/friendship/friends` | ✅ | 1 | ❌ Sprint 1 |
| `POST` | `/chat/` | ✅ | 1 | ❌ Sprint 1 |
| `GET` | `/chat/` | ✅ | 1 | ❌ Sprint 1 |
| `GET` | `/chat/:id/messages` | ✅ | 1 | ❌ Sprint 3 |
| `POST` | `/chat/:id/messages` | ✅ | 1 | ❌ Sprint 3 |
| `POST` | `/message/:id/reaction` | ✅ | 2 | ❌ Sprint 6 |
| `POST` | `/upload` | ✅ | 3 | ❌ Sprint 7 |
| `GET` | `/voice-room/` | ✅ | 4 | ❌ Sprint 8 |
| `POST` | `/voice-room/` | ✅ | 4 | ❌ Sprint 8 |
| `POST` | `/voice-room/:id/join` | ✅ | 4 | ❌ Sprint 8 |
| `POST` | `/voice-room/:id/leave` | ✅ | 4 | ❌ Sprint 8 |
| `GET` | `/ws?token=` | (URL) | 1 | ❌ Sprint 2 |
| `GET` | `/healthz` | ❌ | 5 | ❌ |
| `GET` | `/metrics` | ❌ | 5 | ❌ |

**Итого:** 8 реализовано, 17 нужно сделать.

---

## Порядок реализации

```
Sprint 1 (приоритет сейчас)
├── Миграции 003–005 (индексы, chats, messages, chat_read_cursor)
├── PATCH /friendship/:user_id/status  — принять/отклонить + симм. записи
├── GET  /friendship/friends
├── POST /chat/  — создать DM
└── GET  /chat/  — список чатов

Sprint 2
├── internal/hub/  — Hub, Client, WsMessage
├── GET /ws?token= — WebSocket upgrade
└── WS-событие friend_request при создании заявки

Sprint 3
├── GET  /chat/:id/messages — история с пагинацией
├── POST /chat/:id/messages — отправить + broadcast
├── WS typing indicator
└── WS read + UPSERT chat_read_cursor

Sprint 4–5 (Фаза 2)
├── Distributed Hub через Redis Pub/Sub
├── Presence система (Redis SET TTL)
├── GET /user/:id/presence
└── Rate limiting middleware

Sprint 6 (Фаза 2)
├── Миграция 007 (reactions)
└── POST /message/:id/reaction + WS reaction

Sprint 7 (Фаза 3)
└── POST /upload — MinIO, сжатие изображений

Sprints 8–11 (Фаза 4)
├── Миграция 006 (voice_rooms, room_members)
├── GET/POST /voice-room/
├── POST /voice-room/:id/join — LiveKit token
└── POST /voice-room/:id/leave

Sprints 12–14 (Фаза 5)
├── POST /auth/refresh — refresh tokens
├── GET /healthz
├── GET /metrics — Prometheus
└── Connection pool tuning
```
