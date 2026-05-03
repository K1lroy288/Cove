# Cove — Roadmap развития

**Версия:** 2.0  
**Дата:** 2026-05-03  
**Целевая нагрузка:** 100 000 DAU, ~10 000 одновременных соединений

---

## Целевые показатели нагрузки

| Метрика | Значение |
|---|---|
| DAU (ежедневных активных пользователей) | 100 000 |
| Пиковые одновременные соединения | ~10 000 |
| Сообщений в день | ~5–10 млн |
| WebSocket-соединений на сервере | до 5 000 (2+ инстанса) |
| Запросов к API в пике | ~2 000 RPS |
| Размер таблицы messages (год) | ~1.8 млрд строк |

---

## Архитектура для 100k DAU

### Текущая архитектура (30–50 пользователей)
```
Flutter ──── HTTP/WS ──── Go (1 инстанс) ──── PostgreSQL
```

### Целевая архитектура (100k DAU)
```
                    ┌─────────────────────────────────┐
Flutter ──── HTTPS ─┤  Nginx Load Balancer             │
Flutter ──── WSS  ──┤  (sticky sessions для WS)        │
                    └──────┬──────────────┬────────────┘
                           │              │
                    ┌──────▼──────┐ ┌─────▼──────┐
                    │ Go Instance │ │ Go Instance │  ... (горизонтально)
                    │   (Hub)     │ │   (Hub)     │
                    └──────┬──────┘ └─────┬───────┘
                           │              │
                    ┌──────▼──────────────▼───────┐
                    │         Redis               │
                    │  • Pub/Sub (распред. Hub)   │
                    │  • Presence (онлайн статус) │
                    │  • Rate limiting counters   │
                    │  • Session cache            │
                    └────────────┬────────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
       ┌──────▼──────┐  ┌────────▼──────┐  ┌───────▼──────┐
       │ PostgreSQL  │  │  PostgreSQL   │  │    MinIO     │
       │  (Primary)  │  │  (Replica ×1) │  │   (Media)    │
       └─────────────┘  └───────────────┘  └──────────────┘
                                                    │
                                            ┌───────▼──────┐
                                            │     CDN      │
                                            └──────────────┘
```

**Ключевые принципы масштабирования:**
- Go-инстансы stateless — состояние только в Redis и PostgreSQL
- WebSocket Hub распределён через Redis Pub/Sub: сообщение публикуется в Redis-канал, все инстансы получают и доставляют своим клиентам
- Presence (онлайн-статус) живёт в Redis SET с TTL (heartbeat каждые 30 сек), не в PostgreSQL
- Read-heavy запросы (история сообщений, список чатов) идут на реплику PostgreSQL

---

## Фаза 0 — Фундамент масштабируемости (параллельно с Фазой 1)

> Закладываем правильную архитектуру с первого дня. Дешевле сделать сейчас, чем рефакторить при 10 000 пользователях.

### 0.1 База данных — индексы и схема

Подробно описано в [db-optimization.md](db-optimization.md). Краткий список:

```sql
-- Migration 003: исправить бесполезный индекс friendships
DROP INDEX idx_friendships_status;
CREATE INDEX idx_friendships_friend_status ON friendships(friend_id, status);
CREATE INDEX idx_friendships_user_status   ON friendships(user_id,   status);

-- Migration 004: индексы для сообщений и чатов
CREATE INDEX idx_messages_chat_id     ON messages(chat_id, id DESC);
CREATE INDEX idx_chat_members_user_id ON chat_members(user_id);

-- Migration 005: денормализация последнего сообщения в chats
ALTER TABLE chats
  ADD COLUMN last_message_id      INTEGER REFERENCES messages(id),
  ADD COLUMN last_message_at       TIMESTAMPTZ,
  ADD COLUMN last_message_content  TEXT;

-- Migration 006: заменить read_status на курсор
CREATE TABLE chat_read_cursor (
  chat_id              INTEGER REFERENCES chats(id),
  user_id              INTEGER REFERENCES users(id),
  last_read_message_id INTEGER REFERENCES messages(id),
  updated_at           TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (chat_id, user_id)
);
```

**Симметричные записи дружбы** — при принятии заявки создавать 2 строки в транзакции:
```
(A→B, accepted) + (B→A, accepted)
```
Тогда `GetFriends` = `WHERE user_id=? AND status='accepted'` — использует индекс, нет OR-условий.

### 0.2 Connection Pool

`cmd/main.go` — настройка GORM после подключения:
```go
sqlDB, _ := db.DB()
sqlDB.SetMaxOpenConns(25)       // не перегружать PostgreSQL
sqlDB.SetMaxIdleConns(5)
sqlDB.SetConnMaxLifetime(5 * time.Minute)
```

### 0.3 Структурированные логи

Заменить `log.Printf` на `zerolog` или `zap`:
```go
log.Info().Str("user_id", "42").Str("event", "message_sent").Msg("ok")
```
Без этого при 2000 RPS в логах каша, и проблему в продакшене не найти.

### 0.4 Health check эндпоинт

`GET /healthz` — возвращает `200 OK` с состоянием БД. Нужен для Nginx upstream probes и docker-compose healthcheck.

---

## Фаза 1 — Базовый мессенджер (2–3 недели)

> Цель: два человека находят друг друга, дружат и переписываются в реальном времени.

### Sprint 1 — Завершение дружбы + чаты (1 неделя)

**Бэкенд:**
- [ ] `PATCH /friendship/:user_id/status` — принять/отклонить заявку
  - При `accepted`: INSERT обратной записи в транзакции, затем создать чат автоматически
  - При `declined`: DELETE обеих записей
- [ ] `GET /friendship/friends` — список друзей (`WHERE user_id=? AND status='accepted'`)
- [ ] Миграции 003–006 из Фазы 0
- [ ] Миграция таблиц `chats`, `chat_members`, `messages`, `chat_read_cursor`
- [ ] `POST /chat/` — создать DM-чат (или вернуть существующий)
- [ ] `GET /chat/` — список чатов с превью (использует `last_message_*` колонки)

**Фронтенд:**
- [ ] UI принятия/отклонения заявок (оптимистичный апдейт)
- [ ] Экран списка друзей
- [ ] Кнопка "Написать" → создаёт/открывает чат

### Sprint 2 — WebSocket Hub (1 неделя)

**Бэкенд:**
```
internal/hub/
├── hub.go          — Hub struct, Register/Unregister/Run
├── client.go       — Client struct, readPump/writePump goroutines
└── message.go      — WsMessage{Type, Payload}
```

- [ ] `Hub` — центральный диспетчер с `map[userID]*Client` + mutex
- [ ] `GET /ws?token=<jwt>` — WebSocket upgrade, привязка соединения к userID
- [ ] Типы событий: `message`, `typing`, `read`, `presence`, `friend_request`
- [ ] При отправке заявки в друзья — Push `friend_request` событие через Hub получателю
- [ ] Ping/Pong heartbeat каждые 30 сек (выявляет мёртвые соединения)

**Фронтенд:**
- [ ] `WebSocketService` (`core/services/websocket_service.dart`) — singleton, Stream<WsMessage>
- [ ] Reconnect с exponential backoff: 1s → 2s → 4s → 8s → 30s (max)
- [ ] После reconnect — запрос пропущенных событий (синхронизация)

### Sprint 3 — Обмен сообщениями (1 неделя)

**Бэкенд:**
- [ ] `GET /chat/:id/messages?before=<id>&limit=50` — cursor-based пагинация
- [ ] `POST /chat/:id/messages` — сохранить в БД + обновить `last_message_*` + broadcast через Hub
- [ ] WS-событие `typing` (клиент → сервер → другой клиент)
- [ ] WS-событие `read` → UPSERT в `chat_read_cursor`

**Фронтенд:**
- [ ] `ChatWindowPanel` — `ListView.builder(reverse: true)` + `StreamBuilder` для WS
- [ ] Оптимистичное UI: сообщение добавляется локально сразу, статус обновляется при ACK
- [ ] Typing indicator: 3 анимированные точки, таймаут 3 сек
- [ ] Галочки прочтения: одна (отправлено) → две серые (доставлено) → две синие (прочитано)
- [ ] Подгрузка истории при скролле вверх (infinite scroll с `before` курсором)

---

## Фаза 2 — Масштабирование Hub + богатый опыт (2–3 недели)

> К этому моменту может появиться несколько сотен активных пользователей. Нужно перевести Hub на Redis.

### Sprint 4 — Distributed Hub (Redis Pub/Sub)

> Без этого нельзя запустить 2+ инстанса Go. Делать до того, как стало проблемой.

**Архитектура:**
```
Go Instance 1              Go Instance 2
  Hub (local)                Hub (local)
       │                          │
       └──── Redis Pub/Sub ────────┘
              channel: chat:{chat_id}
              channel: user:{user_id}
```

**Реализация:**
- [ ] `internal/hub/redis_hub.go` — при broadcast публиковать в Redis-канал
- [ ] Подписка на каналы при старте каждого инстанса
- [ ] Формат Redis-сообщения: тот же JSON envelope `{type, payload}`
- [ ] Nginx upstream: sticky sessions по `user_id` hash (для WebSocket)

**Инфраструктура:**
- [ ] `docker-compose.yml` — добавить Redis сервис
- [ ] `config.go` — добавить `Redis.URL` параметр

### Sprint 5 — Присутствие (Presence) через Redis

- [ ] При WS-подключении: `SETEX presence:{user_id} 60 "online"`
- [ ] Heartbeat каждые 30 сек: обновлять TTL
- [ ] При WS-отключении: `DEL presence:{user_id}` + broadcast `presence: offline`
- [ ] `GET /user/:id/presence` — проверить онлайн-статус (чтение из Redis)
- [ ] Фронтенд: зелёная точка рядом с именем друга

### Sprint 6 — Богатый опыт общения

**Реакции:**
- [ ] Миграция таблицы `reactions`
- [ ] `POST /message/:id/reaction` — toggle (добавить/убрать)
- [ ] WS-событие `reaction` для реал-тайм обновления у всех участников чата
- [ ] Фронтенд: long press → emoji picker, реакции под пузырём с счётчиком + анимация

**Ответы/цитаты:**
- [ ] Поле `reply_to_id` уже в схеме (`messages`)
- [ ] Swipe вправо → preview цитируемого сообщения над полем ввода
- [ ] Рендер цитаты внутри пузыря, тап → scroll to original

**Rate Limiting:**
- [ ] Middleware на Gin: Redis-based token bucket
- [ ] Лимиты: 60 сообщений/мин на пользователя, 10 запросов/мин на `/auth/*` per IP
- [ ] Ответ `429 Too Many Requests` с заголовком `Retry-After`

---

## Фаза 3 — Медиафайлы (1–2 недели)

> Медиа отдаётся через CDN, не через Go-сервер — это критично для нагрузки.

### Sprint 7 — Загрузка и хранение медиа

**Инфраструктура:**
- [ ] MinIO в `docker-compose.yml` (S3-совместимый, self-hosted)
- [ ] Bucket `cove-media` с публичным чтением через CDN (или presigned URLs)

**Бэкенд:**
- [ ] `POST /upload` — получить файл, валидировать (тип, размер ≤ 10 MB), сохранить в MinIO, вернуть URL
- [ ] Сжатие изображений перед сохранением (`imaging` пакет): max 1920px, JPEG 85%
- [ ] Thumbnail: 200×200 для превью в чате
- [ ] Поле `type` в `messages`: `text | image | voice | file`

**Фронтенд:**
- [ ] Image picker + upload progress indicator
- [ ] Превью изображений в чате (thumbnail, тап → fullscreen)
- [ ] Голосовые сообщения: запись + waveform + воспроизведение

---

## Фаза 4 — Голосовые комнаты (3–4 недели)

> Ключевая фича Cove. Требует отдельной инфраструктуры SFU.

### Sprint 8–9 — Инфраструктура голоса

**Инфраструктура:**
- [ ] **LiveKit Server** в `docker-compose.yml` — open-source SFU
- [ ] **coturn** — TURN-сервер для обхода NAT/firewall (обязателен с первого дня)
- [ ] TLS-сертификат для WSS (coturn требует DTLS)

**Почему LiveKit, а не P2P WebRTC:**
| | P2P Mesh | LiveKit SFU |
|---|---|---|
| До 4 человек | ✅ Просто | ✅ Работает |
| 5–15 человек | ❌ N×(N-1) потоков у каждого | ✅ 1 поток на клиента |
| Масштабирование | ❌ Невозможно | ✅ Горизонтально |
| Запись комнаты (будущее) | ❌ | ✅ |

**Бэкенд:**
- [ ] Миграция таблиц `voice_rooms`, `room_members`
- [ ] `POST /voice-room/` — создать комнату + сгенерировать LiveKit token для создателя
- [ ] `GET /voice-room/` — список активных комнат
- [ ] `POST /voice-room/:id/join` — сгенерировать LiveKit token для участника
- [ ] `POST /voice-room/:id/leave` — обновить `room_members`, если 0 участников → `is_active=false`
- [ ] WS-событие `room_update` — рассылка при join/leave

### Sprint 10–11 — UI голосовых комнат

**Фронтенд:**
- [ ] Список комнат в сайдбаре — видны всегда, вход одним тапом
- [ ] Страница комнаты: сетка аватаров участников
- [ ] **Speaking indicator** — зелёный пульсирующий ободок (LiveKit AudioAnalyser)
- [ ] Иконки статуса: замьючен 🎙️✗, deafened 🎧✗, говорит 🎙️
- [ ] **Persistent mini-bar** — остаётся внизу при навигации (как у Discord)
- [ ] Push-to-talk / Voice Activity Detection — переключатель
- [ ] Noise cancellation + Echo cancellation (через `flutter_webrtc` mediaConstraints)
- [ ] Индикатор качества соединения (хорошее/среднее/плохое)
- [ ] "Leave Quietly" — тихий выход без уведомления

---

## Фаза 5 — Безопасность и Production-ready (2 недели)

### Sprint 12 — Безопасность

- [ ] **JWT refresh tokens**: access token 15 мин + refresh token 30 дней
  - `POST /auth/refresh` — обмен refresh → новый access + новый refresh (rotation)
  - Хранить refresh в httpOnly cookie (или secure storage на Flutter)
  - При logout — инвалидировать refresh (занести в Redis blacklist с TTL = оставшееся время жизни)
- [ ] **HTTPS + WSS** в продакшене — Nginx с Let's Encrypt (certbot)
- [ ] **Input validation**: middleware на все POST/PATCH — проверка длины, типов, спецсимволов
- [ ] **SQL injection**: GORM параметризованные запросы (уже ✅), не форматировать SQL вручную
- [ ] **Rate limiting** уже в Фазе 2 — убедиться что покрыты все эндпоинты

### Sprint 13 — Мониторинг и наблюдаемость

- [ ] **Prometheus metrics** (`/metrics`): RPS, латентность по эндпоинтам, активные WS-соединения, размер очередей Hub
- [ ] **Grafana dashboard** — визуализация метрик
- [ ] **Structured logging** (zerolog): request_id в каждой строке, время ответа, user_id
- [ ] **Distributed tracing** (опционально): OpenTelemetry → Jaeger

### Sprint 14 — Оффлайн и Push

- [ ] **Оффлайн-кэш** на Flutter (SQLite через `drift`): последние 200 сообщений на чат
- [ ] **Синхронизация при reconnect**: `GET /chat/:id/messages?after=<last_known_id>`
- [ ] **Firebase Cloud Messaging**: push при новом сообщении когда приложение в фоне
- [ ] Настройки уведомлений: все / только упоминания / отключить

---

## Инфраструктура — Docker Compose (целевая)

```yaml
services:
  nginx:          # Load balancer + SSL termination
  go-app-1:       # Go instance 1
  go-app-2:       # Go instance 2
  postgres:       # PostgreSQL primary
  postgres-replica: # PostgreSQL read replica (Streaming Replication)
  redis:          # Redis (Hub Pub/Sub + Presence + Rate limiting)
  minio:          # Object storage for media
  livekit:        # Voice SFU
  coturn:         # TURN server for WebRTC NAT traversal
  prometheus:     # Metrics scraping
  grafana:        # Metrics visualization
```

---

## Сводная таблица эндпоинтов

| Метод | Path | Фаза | Статус |
|---|---|---|---|
| `POST` | `/auth/register` | 1 | ✅ |
| `POST` | `/auth/login` | 1 | ✅ |
| `POST` | `/auth/refresh` | 5 | ❌ |
| `GET` | `/user/search?q=` | 1 | ✅ |
| `GET` | `/user/:id` | 1 | ✅ |
| `GET` | `/user/:id/presence` | 2 | ❌ |
| `POST` | `/friendship/` | 1 | ✅ |
| `GET` | `/friendship/pending` | 1 | ✅ |
| `GET` | `/friendship/pending/count` | 1 | ✅ |
| `PATCH` | `/friendship/:user_id/status` | 1 | ❌ Sprint 1 |
| `GET` | `/friendship/friends` | 1 | ❌ Sprint 1 |
| `POST` | `/chat/` | 1 | ❌ Sprint 1 |
| `GET` | `/chat/` | 1 | ❌ Sprint 1 |
| `GET` | `/chat/:id/messages` | 1 | ❌ Sprint 3 |
| `POST` | `/chat/:id/messages` | 1 | ❌ Sprint 3 |
| `POST` | `/message/:id/reaction` | 2 | ❌ Sprint 6 |
| `POST` | `/upload` | 3 | ❌ Sprint 7 |
| `GET` | `/voice-room/` | 4 | ❌ Sprint 8 |
| `POST` | `/voice-room/` | 4 | ❌ Sprint 8 |
| `POST` | `/voice-room/:id/join` | 4 | ❌ Sprint 8 |
| `POST` | `/voice-room/:id/leave` | 4 | ❌ Sprint 8 |
| `GET` | `/ws?token=` | 1 | ❌ Sprint 2 |
| `GET` | `/healthz` | 0 | ❌ |
| `GET` | `/metrics` | 5 | ❌ |

---

## Приоритетный порядок реализации

```
Неделя 1–3: Фаза 1
├── DB миграции (индексы, chat_read_cursor, last_message)
├── Симметричные записи дружбы
├── PATCH friendship status + GET friends
├── POST/GET /chat/ + GET /chat/:id/messages + POST /chat/:id/messages
├── WebSocket Hub (Go) + WebSocket клиент (Flutter)
└── Typing indicator + статус прочтения

Неделя 4–6: Фаза 2
├── Redis Pub/Sub для распределённого Hub
├── Presence система через Redis
├── Реакции + ответы/цитаты
└── Rate limiting

Неделя 7–8: Фаза 3
└── Загрузка медиа (MinIO + CDN)

Неделя 9–12: Фаза 4
├── LiveKit SFU + coturn
├── Голосовые комнаты (бэкенд)
└── UI голосовых комнат (speaking indicator, mini-bar)

Неделя 13–14: Фаза 5
├── JWT refresh tokens
├── HTTPS/WSS production
├── Prometheus + Grafana
├── Оффлайн-кэш + Push-уведомления
└── Rate limiting на все эндпоинты
```

---

## Технический стек (итоговый)

| Слой | Технология | Назначение |
|---|---|---|
| Frontend | Flutter + Dart | Кроссплатформенный UI |
| State management | Provider → Riverpod (Фаза 2) | Реактивный state |
| Backend | Go 1.22 + Gin | HTTP API + WebSocket |
| ORM | GORM | PostgreSQL ORM |
| База данных | PostgreSQL 16 | Хранение данных |
| Read replica | PostgreSQL Streaming Replication | Масштабирование чтения |
| Кэш / Pub-Sub | Redis 7 | Hub, presence, rate limiting |
| Connection pooling | PgBouncer (Фаза 5) | Защита PostgreSQL от перегрузки |
| Реал-тайм | Gorilla WebSocket + Redis Hub | Сообщения, typing, presence |
| Голос | WebRTC + LiveKit SFU | Голосовые комнаты |
| NAT traversal | coturn (TURN) | WebRTC за NAT |
| Медиа | MinIO (S3-совместимый) | Файлы, изображения |
| Балансировщик | Nginx | TLS, upstream, sticky WS |
| Мониторинг | Prometheus + Grafana | Метрики, алерты |
| Логирование | zerolog | Структурированные логи |
| Уведомления | Firebase Cloud Messaging | Push в фоне |
| Безопасность | JWT (access + refresh), TLS | Аутентификация |

---

*Документ составлен на основе RESEARCH.md, PRD.md, backend-plan.md и db-optimization.md*
