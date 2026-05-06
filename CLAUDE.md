# Cove — CLAUDE.md

## Проект

**Cove** — приватный мессенджер с постоянными голосовыми комнатами для небольших групп друзей.
Discord-уровень голоса + простота Telegram + приватность по умолчанию.
Цель: **100k DAU**, ~10k одновременных WS-соединений, ~2k RPS в пике.

**Стек:** Go 1.22 + Gin · PostgreSQL 16 · GORM · Gorilla WebSocket · Flutter (frontend) · LiveKit SFU (Phase 4) · Redis (Phase 2) · MinIO (Phase 3)

---

## Структура проекта

```
cove/
├── backend/
│   ├── cmd/main.go                        # Точка входа: роутинг, DI
│   ├── internal/
│   │   ├── config/config.go               # Env-конфиг (sync.Once singleton)
│   │   ├── db/
│   │   │   ├── migrator.go                # Запуск миграций при старте
│   │   │   └── migration/                 # SQL-файлы: 001_*.up.sql / 001_*.down.sql
│   │   ├── model/                         # GORM-сущности (не выставлять в API)
│   │   ├── DTO/                           # API-контракты (входящие запросы + ответы)
│   │   ├── repository/                    # Только DB-запросы
│   │   ├── service/                       # Бизнес-логика (без http.*)
│   │   ├── handler/                       # Gin-хендлеры (только HTTP)
│   │   ├── middleware/                    # auth.go (JWT), rate_limit.go (Phase 2)
│   │   └── utils/generate_jwt.go
│   └── deployments/
│       ├── docker-compose.yml             # PostgreSQL 17 на порту 5433
│       └── Dockerfile                     # Multi-stage, статичный бинарь
├── frontend/                              # Flutter, Provider → Riverpod (Phase 2)
├── backend-plan.md                        # ИСТОЧНИК ИСТИНЫ: все эндпоинты, схемы запросов/ответов
├── PRD.md
├── RESEARCH.md
└── ROADMAP.md
```

---

## Команды

```bash
# База данных
docker compose -f backend/deployments/docker-compose.yml up -d

# Запуск сервера (порт 3425)
cd backend && go run ./cmd/main.go

# Сборка и проверка
cd backend && go build ./... && go vet ./...
```

---

## Архитектура (строгие слои)

```
Handler → Service → Repository → DB
```

| Слой | Отвечает за | Не делает |
|---|---|---|
| **Handler** | Парсинг JSON, извлечение user_id из JWT, HTTP-статусы | Бизнес-логику |
| **Service** | Бизнес-правила, оркестрация репозиториев | HTTP-типы, SQL |
| **Repository** | SQL-запросы, транзакции | Бизнес-логику |
| **Model** | GORM-сущности БД | Появляться в API-ответах |
| **DTO** | API-контракты (вход и выход) | SQL, бизнес-логику |

**Правило:** никогда не пропускать слои. Никогда не возвращать `model.*` напрямую из хендлера.

---

## База данных

### Миграции

- Файлы в `internal/db/migration/`, нумерация `NNN_name.up.sql` / `NNN_name.down.sql`
- Запускаются автоматически при старте через `golang-migrate`
- Всегда создавать оба файла (up + down)

### Когда GORM ORM, когда raw SQL

| Используй | Когда |
|---|---|
| GORM ORM (`r.DB.Where(...).Find(...)`) | Простые запросы, транзакции, INSERT, UPDATE |
| `r.DB.Raw(...)` | Сложные JOIN-ы с вычисляемыми полями (GetChats, GetChatDTO, FindExistingChat) |
| **Не использовать Squirrel** | Динамический WHERE → GORM chainable API (см. ниже) |

**Динамический WHERE через GORM:**
```go
q := r.DB.Where("chat_id = ? AND deleted_at IS NULL", chatID)
if beforeID != nil {
    q = q.Where("id < ?", *beforeID)
}
q.Order("id DESC").Limit(limit).Find(&messages)
```

### Connection Pool (уже настроен под 100k DAU, не трогать без бенчмарка)

```go
sqlDB.SetMaxOpenConns(25)
sqlDB.SetMaxIdleConns(5)
sqlDB.SetConnMaxLifetime(5 * time.Minute)
```

---

## Ключевые неочевидные решения

### 1. Симметричные записи дружбы
При принятии заявки создаются **две строки** в одной транзакции:
```sql
(A→B, accepted) + (B→A, accepted)
```
`GetFriends` = `WHERE user_id=? AND status='accepted'` — один индекс, без OR.
`GetPendingRequests` = `WHERE friend_id=? AND status='pending'`.

### 2. `chat_read_cursor` вместо `read_status`
`read_status(message_id, user_id)` рос как O(messages × users) → миллиарды строк.
`chat_read_cursor(chat_id, user_id, last_read_message_id)` — O(chats × users).
Непрочитанных: `COUNT(*) FROM messages WHERE chat_id=? AND id > last_read_message_id`.

### 3. Денормализация `chats`
Поля `last_message_id`, `last_message_at`, `last_message_content` обновляются при каждой отправке.
`GET /chat/` — простой JOIN без субзапроса на каждый чат.

### 4. Пагинация сообщений (GetMessages)
```
ORDER BY id DESC + LIMIT  →  эффективный Index Range Scan
reverse(slice)             →  хронологический порядок для клиента
```
Индекс: `idx_messages_chat_id ON messages(chat_id, id DESC)`.

### 5. Индексы friendships
```sql
idx_friendships_friend_status (friend_id, status)  -- GetPendingRequests
idx_friendships_user_status   (user_id,   status)  -- GetFriends
-- idx_friendships_status -- НЕ СОЗДАВАТЬ (3 значения, не используется оптимизатором)
```

---

## Масштаб (100k DAU)

| Что | Решение |
|---|---|
| WebSocket Hub Phase 1 | In-memory map (Go), sticky sessions на Nginx |
| WebSocket Hub Phase 2 | Redis Pub/Sub — Go-инстансы stateless |
| Presence (онлайн-статус) | Redis `SET presence:{id} EX 60`, **не** в PostgreSQL |
| Read-heavy запросы | PostgreSQL read replica (Phase 2+) |
| Rate limiting | Redis token bucket: 60 msg/min/user, 10 auth/min/IP (Phase 2) |

**Принцип Phase 2+:** Go-инстансы не хранят состояние — всё в Redis и PostgreSQL.

---

## Auth

- **JWT HS256**, TTL 24ч, claims: `user_id` + `username`
- Middleware инжектит в Gin context → хендлеры вызывают `currentUserID(c)`
- **WebSocket**: токен передаётся в query-параметре `?token=` (заголовки недоступны после upgrade)

---

## Конвенции

### Именование
- Файлы: `snake_case` (`chat_repository.go`, `user_handler.go`)
- Структуры: `PascalCase` единственное число (`User`, `Chat`, `ChatReadCursor`)
- DTO: суффикс `DTO` или по назначению (`ChatDTO`, `CreateChatRequest`)
- JSON: `snake_case`
- Язык комментариев: русский

### Известные опечатки в именах файлов (не переименовывать без обновления импортов)
- `internal/model/frindship.go` (не `friendship.go`)
- `internal/repository/messsage_repository.go` (не `message_repository.go`)

### Обработка ошибок
```
Repository  →  возвращает raw error
Service     →  оборачивает при необходимости (fmt.Errorf("...: %w", err))
Handler     →  маппит на HTTP:
                 pgx error code 23505  →  409 Conflict
                 gorm.ErrRecordNotFound →  404 Not Found
                 остальное             →  500 + log.Printf
```
Всегда логировать ошибку (`log.Printf`) перед возвратом HTTP-ответа.

---

## Текущий статус (Sprint 1)

**Реализовано:** `POST /auth/register`, `POST /auth/login`, `GET /user/*`, `POST /friendship/`, `GET /friendship/pending`, `GET /friendship/pending/count`

**В работе (Sprint 1):**
- `PATCH /friendship/:user_id/status` — принять/отклонить заявку
- `GET /friendship/friends`
- `POST /chat/` — создать или найти DM
- `GET /chat/` — список чатов

**Далее:** WebSocket Hub → сообщения CRUD → Redis → голосовые комнаты (LiveKit) → медиафайлы (MinIO)

Полная спецификация всех эндпоинтов с форматами запросов и ответов — в [backend-plan.md](backend-plan.md).
