# Cove — Backend API Plan

**Base URL:** `http://localhost:3425`  
**Формат данных:** JSON  
**Версия плана:** 1.0 (2026-05-02)

---

## Общие соглашения

### Аутентификация
Все защищённые эндпоинты требуют заголовок:
```
Authorization: Bearer <jwt_token>
```
Токен выдаётся при логине. При отсутствии или невалидности токена — `401 Unauthorized`.

### Формат ошибок
Все ошибки возвращают JSON с полем `message`:
```json
{ "message": "Описание ошибки на русском" }
```

### Коды статусов — общие правила
| Код | Когда использовать |
|---|---|
| `200` | Успешный GET или успешный PATCH/POST без нового ресурса |
| `201` | Успешное создание ресурса (POST) |
| `400` | Невалидный JSON, отсутствующие поля, бизнес-ошибка (дубликат, самодобавление) |
| `401` | Отсутствует или невалидный JWT |
| `403` | Токен валидный, но нет прав на действие |
| `404` | Ресурс не найден |
| `409` | Конфликт — ресурс уже существует |
| `500` | Внутренняя ошибка сервера |

---

## 1. Auth — Аутентификация

### `POST /auth/register` ✅ Реализовано

Регистрация нового пользователя.

**Аутентификация:** не требуется

**Тело запроса:**
```json
{
  "username": "alice",
  "password": "secret123"
}
```

| Поле | Тип | Обязательно | Описание |
|---|---|---|---|
| `username` | string | ✅ | Уникальный никнейм |
| `password` | string | ✅ | Пароль в открытом виде (хешируется сервером) |

**Успешный ответ — `201 Created`:**
```
(тело пустое)
```

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | Невалидный JSON или пустые поля | `{ "message": "Неверный формат данных" }` |
| `400` | Username уже занят (unique violation) | `{ "message": "Пользователь с таким именем уже существует" }` |
| `500` | Ошибка БД | *(пустое тело)* |

---

### `POST /auth/login` ✅ Реализовано

Вход по username + password, возвращает JWT.

**Аутентификация:** не требуется

**Тело запроса:**
```json
{
  "username": "alice",
  "password": "secret123"
}
```

**Успешный ответ — `200 OK`:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "userId": 42,
  "username": "alice"
}
```

| Поле | Тип | Описание |
|---|---|---|
| `token` | string | JWT access token |
| `userId` | number | ID пользователя (целое число) |
| `username` | string | Username пользователя |

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | Невалидный JSON | `{ "message": "Неверный формат данных" }` |
| `401` | Username не найден | `{ "message": "Неверное имя пользователя или пароль" }` |
| `401` | Неверный пароль | `{ "message": "Неверное имя пользователя или пароль" }` |
| `500` | Ошибка генерации JWT | `{ "message": "Ошибка аутентификации. Попробуйте позже" }` |

---

## 2. User — Пользователи

### `GET /user/search?q=<query>` ✅ Реализовано

Поиск пользователя по username (точное совпадение) или по числовому ID.  
Логика: сначала ищет по username, если не найден и `q` — число, ищет по ID.

**Аутентификация:** не требуется  
**Query параметры:** `q` — строка поиска (username или ID)

**Успешный ответ — `200 OK`:**
```json
{
  "id": 42,
  "username": "alice"
}
```

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | Параметр `q` не указан | `{ "message": "Параметр поиска не указан" }` |
| `404` | Пользователь не найден | `{ "message": "Пользователь не найден" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

### `GET /user/:id` ✅ Реализовано

Получить пользователя по числовому ID.

**Аутентификация:** не требуется  
**Path параметры:** `id` — числовой ID

**Успешный ответ — `200 OK`:**
```json
{
  "id": 42,
  "username": "alice"
}
```

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | `id` не является числом | `{ "message": "Неверный формат данных" }` |
| `404` | Пользователь не найден | `{ "message": "Пользователь не найден" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

### `GET /user/username/:username` ✅ Реализовано

Получить пользователя по точному username.

**Аутентификация:** не требуется  
**Path параметры:** `username` — строка

> **Важно:** этот маршрут зарегистрирован **до** `/:id`, иначе Gin захватит его как числовой ID.

**Успешный ответ — `200 OK`:** аналогично `GET /user/:id`

**Ошибки:** аналогично `GET /user/:id`

---

## 3. Friendship — Дружба

### `POST /friendship/` ✅ Реализовано

Отправить заявку в друзья. Создаёт запись со статусом `pending`.

**Аутентификация:** требуется (JWT)

**Тело запроса:**
```json
{
  "user_id": 1,
  "friend_id": 2,
  "status": "pending"
}
```

| Поле | Тип | Описание |
|---|---|---|
| `user_id` | number | ID отправителя заявки |
| `friend_id` | number | ID получателя заявки |
| `status` | string | Всегда `"pending"` при создании |

**Успешный ответ — `201 Created`:**
```
(тело пустое)
```

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | Невалидный JSON | `{ "message": "Неверный формат данных" }` |
| `400` | `user_id == friend_id` | `{ "message": "Нельзя добавить себя в друзья" }` |
| `400` | Заявка уже существует (unique violation) | `{ "message": "Запись о дружбе уже существует" }` |
| `500` | Ошибка БД | *(пустое тело)* |

---

### `GET /friendship/pending?user_id=<id>` ✅ Реализовано

Получить список входящих заявок в друзья (статус `pending`, где `friend_id = user_id`).

**Аутентификация:** требуется (JWT)  
**Query параметры:** `user_id` — ID текущего пользователя

**Успешный ответ — `200 OK`:**
```json
[
  { "user_id": 7, "username": "bob" },
  { "user_id": 15, "username": "charlie" }
]
```

Возвращает пустой массив `[]` если заявок нет.

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | `user_id` не является числом | `{ "message": "Неверный формат user_id" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

### `GET /friendship/pending/count?user_id=<id>` ✅ Реализовано

Получить количество входящих заявок.

**Аутентификация:** требуется (JWT)  
**Query параметры:** `user_id` — ID текущего пользователя

**Успешный ответ — `200 OK`:**
```json
{ "count": 3 }
```

**Ошибки:** аналогично `GET /friendship/pending`

---

### `PATCH /friendship/:user_id/status` ❌ Не реализовано

Принять или отклонить входящую заявку от пользователя с ID `:user_id`.

**Аутентификация:** требуется (JWT)  
**Path параметры:** `user_id` — ID отправителя заявки

**Тело запроса:**
```json
{
  "status": "accepted"
}
```

| Поле | Тип | Допустимые значения |
|---|---|---|
| `status` | string | `"accepted"` или `"declined"` |

**Логика:**
- Найти запись `WHERE user_id = :user_id AND friend_id = <из JWT> AND status = 'pending'`
- Если статус `"accepted"` — обновить статус на `accepted`, создать обратную запись (`user_id = me, friend_id = :user_id, status = accepted`) для симметрии
- Если статус `"declined"` — удалить запись (или обновить статус, если хранить историю)

**Успешный ответ — `200 OK`:**
```json
{ "message": "Заявка принята" }
```
или
```json
{ "message": "Заявка отклонена" }
```

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | Невалидный JSON | `{ "message": "Неверный формат данных" }` |
| `400` | Недопустимый статус (не accepted/declined) | `{ "message": "Недопустимый статус" }` |
| `400` | `user_id` не число | `{ "message": "Неверный формат user_id" }` |
| `401` | Нет токена | `{ "message": "Необходима авторизация" }` |
| `404` | Заявка не найдена | `{ "message": "Заявка не найдена" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

### `GET /friendship/friends?user_id=<id>` ❌ Не реализовано

Получить список друзей (записи со статусом `accepted`).

**Аутентификация:** требуется (JWT)  
**Query параметры:** `user_id` — ID пользователя

**Логика:** выбрать все записи `WHERE (user_id = ? OR friend_id = ?) AND status = 'accepted'`, вернуть данные **другого** участника.

**Успешный ответ — `200 OK`:**
```json
[
  { "id": 7, "username": "bob" },
  { "id": 15, "username": "charlie" }
]
```

Возвращает `[]` если друзей нет.

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | `user_id` не число | `{ "message": "Неверный формат user_id" }` |
| `401` | Нет токена | `{ "message": "Необходима авторизация" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

## 4. Chat — Чаты (Direct Messages)

> Все эндпоинты этой группы ❌ Не реализованы.

### `GET /chat/`

Получить список чатов текущего пользователя.

**Аутентификация:** требуется (JWT — берёт `user_id` из токена)

**Логика:** `SELECT` из `chat_members JOIN chats JOIN users` — найти все чаты, в которых участвует текущий пользователь, и вернуть данные партнёра + превью последнего сообщения.

**Успешный ответ — `200 OK`:**
```json
[
  {
    "id": 101,
    "partner_id": 7,
    "partner_name": "bob",
    "last_message": "Привет!",
    "last_message_at": "2026-05-02T14:30:00Z"
  },
  {
    "id": 102,
    "partner_id": 15,
    "partner_name": "charlie",
    "last_message": null,
    "last_message_at": null
  }
]
```

| Поле | Тип | Описание |
|---|---|---|
| `id` | number | ID чата |
| `partner_id` | number | ID собеседника |
| `partner_name` | string | Username собеседника |
| `last_message` | string\|null | Текст последнего сообщения |
| `last_message_at` | string\|null | ISO 8601 timestamp последнего сообщения |

Возвращает `[]` если чатов нет.

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `401` | Нет токена | `{ "message": "Необходима авторизация" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

### `POST /chat/`

Создать DM-чат с другом. Если чат уже существует — вернуть существующий.

**Аутентификация:** требуется (JWT)

**Тело запроса:**
```json
{
  "friend_id": 7
}
```

**Логика:**
1. Проверить, что `friend_id` является другом текущего пользователя (статус `accepted`)
2. Проверить, нет ли уже чата между ними
3. Если есть — вернуть существующий `200 OK`
4. Если нет — создать чат + добавить обоих в `chat_members`, вернуть `201 Created`

**Успешный ответ — `201 Created` (новый)** или **`200 OK` (уже существует):**
```json
{
  "id": 101,
  "partner_id": 7,
  "partner_name": "bob",
  "last_message": null,
  "last_message_at": null
}
```

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | Невалидный JSON | `{ "message": "Неверный формат данных" }` |
| `400` | `friend_id` не указан | `{ "message": "Не указан friend_id" }` |
| `401` | Нет токена | `{ "message": "Необходима авторизация" }` |
| `403` | Пользователь не является другом | `{ "message": "Можно создать чат только с другом" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

## 5. Messages — Сообщения

> Все эндпоинты этой группы ❌ Не реализованы.

### `GET /chat/:id/messages`

Получить историю сообщений чата с cursor-based пагинацией.

**Аутентификация:** требуется (JWT)  
**Path параметры:** `id` — ID чата  
**Query параметры:**
| Параметр | Тип | Дефолт | Описание |
|---|---|---|---|
| `limit` | number | 50 | Кол-во сообщений |
| `before` | number | — | ID сообщения — вернуть сообщения **старше** него (для подгрузки истории вверх) |

**Логика:**
- `WHERE chat_id = ? [AND id < ?before] ORDER BY id DESC LIMIT ?limit`
- Затем реверс массива, чтобы вернуть в хронологическом порядке

**Успешный ответ — `200 OK`:**
```json
[
  {
    "id": 1001,
    "chat_id": 101,
    "sender_id": 42,
    "content": "Привет!",
    "type": "text",
    "created_at": "2026-05-02T14:25:00Z"
  },
  {
    "id": 1002,
    "chat_id": 101,
    "sender_id": 7,
    "content": "Привет! Как дела?",
    "type": "text",
    "created_at": "2026-05-02T14:26:00Z"
  }
]
```

| Поле | Тип | Описание |
|---|---|---|
| `id` | number | ID сообщения |
| `chat_id` | number | ID чата |
| `sender_id` | number | ID отправителя |
| `content` | string | Текст сообщения |
| `type` | string | `"text"` \| `"image"` \| `"voice"` \| `"file"` |
| `created_at` | string | ISO 8601 |

Возвращает `[]` если сообщений нет.

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | `id` чата не число | `{ "message": "Неверный формат данных" }` |
| `401` | Нет токена | `{ "message": "Необходима авторизация" }` |
| `403` | Пользователь не участник чата | `{ "message": "Нет доступа к этому чату" }` |
| `404` | Чат не найден | `{ "message": "Чат не найден" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

### `POST /chat/:id/messages`

Отправить сообщение в чат.

**Аутентификация:** требуется (JWT — берёт `sender_id` из токена)  
**Path параметры:** `id` — ID чата

**Тело запроса:**
```json
{
  "content": "Привет! Как дела?",
  "type": "text"
}
```

| Поле | Тип | Дефолт | Описание |
|---|---|---|---|
| `content` | string | — | Текст сообщения |
| `type` | string | `"text"` | Тип сообщения |

**Успешный ответ — `201 Created`:**
```json
{
  "id": 1003,
  "chat_id": 101,
  "sender_id": 42,
  "content": "Привет! Как дела?",
  "type": "text",
  "created_at": "2026-05-02T14:30:00Z"
}
```

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | Невалидный JSON или пустой `content` | `{ "message": "Неверный формат данных" }` |
| `401` | Нет токена | `{ "message": "Необходима авторизация" }` |
| `403` | Не участник чата | `{ "message": "Нет доступа к этому чату" }` |
| `404` | Чат не найден | `{ "message": "Чат не найден" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

> **После сохранения в БД** — сообщение нужно транслировать через WebSocket Hub всем участникам чата (событие `"message"`). Это часть Phase 1.2.

---

## 6. Voice Rooms — Голосовые комнаты

> Все эндпоинты этой группы ❌ Не реализованы.

### `GET /voice-room/`

Получить список активных голосовых комнат.

**Аутентификация:** требуется (JWT)

**Успешный ответ — `200 OK`:**
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

| Поле | Тип | Описание |
|---|---|---|
| `id` | number | ID комнаты |
| `name` | string | Название комнаты |
| `created_by` | number | ID создателя |
| `is_active` | bool | Активна ли комната |
| `members` | array | Текущие участники |
| `members[].user_id` | number | ID участника |
| `members[].username` | string | Username участника |
| `members[].is_muted` | bool | Замьючен ли участник |

Возвращает `[]` если нет активных комнат.

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `401` | Нет токена | `{ "message": "Необходима авторизация" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

### `POST /voice-room/`

Создать новую голосовую комнату и автоматически войти в неё.

**Аутентификация:** требуется (JWT)

**Тело запроса:**
```json
{
  "name": "Вечерний чилл"
}
```

**Успешный ответ — `201 Created`:**
```json
{
  "id": 2,
  "name": "Вечерний чилл",
  "created_by": 42,
  "is_active": true,
  "members": [
    { "user_id": 42, "username": "alice", "is_muted": false }
  ]
}
```

Создатель автоматически добавляется в `room_members`.

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | Невалидный JSON или пустое `name` | `{ "message": "Неверный формат данных" }` |
| `401` | Нет токена | `{ "message": "Необходима авторизация" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

### `POST /voice-room/:id/join`

Присоединиться к голосовой комнате.

**Аутентификация:** требуется (JWT)  
**Path параметры:** `id` — ID комнаты

**Тело запроса:** пустое

**Логика:**
1. Проверить, что комната активна
2. Добавить пользователя в `room_members` (upsert — если уже есть, не падать)
3. Вернуть полный объект комнаты с текущим списком участников
4. Разослать через WebSocket событие `room_update` всем участникам комнаты

**Успешный ответ — `200 OK`:**
```json
{
  "id": 1,
  "name": "Общая комната",
  "created_by": 42,
  "is_active": true,
  "members": [
    { "user_id": 42, "username": "alice", "is_muted": false },
    { "user_id": 7,  "username": "bob",   "is_muted": false },
    { "user_id": 99, "username": "new_user", "is_muted": false }
  ]
}
```

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | `id` не число | `{ "message": "Неверный формат данных" }` |
| `401` | Нет токена | `{ "message": "Необходима авторизация" }` |
| `404` | Комната не найдена | `{ "message": "Комната не найдена" }` |
| `410` | Комната неактивна (все вышли) | `{ "message": "Комната уже закрыта" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

### `POST /voice-room/:id/leave`

Покинуть голосовую комнату.

**Аутентификация:** требуется (JWT)  
**Path параметры:** `id` — ID комнаты

**Тело запроса:** пустое

**Логика:**
1. Удалить пользователя из `room_members`
2. Если участников не осталось — установить `is_active = false` на комнате
3. Разослать через WebSocket событие `room_update` оставшимся участникам

**Успешный ответ — `200 OK`:**
```json
{ "message": "Вы покинули комнату" }
```

**Ошибки:**
| Код | Условие | Тело |
|---|---|---|
| `400` | `id` не число | `{ "message": "Неверный формат данных" }` |
| `401` | Нет токена | `{ "message": "Необходима авторизация" }` |
| `404` | Комната не найдена | `{ "message": "Комната не найдена" }` |
| `500` | Ошибка БД | `{ "message": "Ошибка сервера" }` |

---

## 7. WebSocket — Реал-тайм события

> ❌ Не реализовано. Планируется в Phase 1.2.

### `GET /ws?token=<jwt>`

WebSocket upgrade. Аутентификация через query-параметр `token`.

**После подключения** — сервер привязывает соединение к `user_id` из JWT и регистрирует клиента в Hub.

### Формат сообщений

Все сообщения — JSON с обёрткой `type` + `payload`:

```json
{ "type": "<event_type>", "payload": { ... } }
```

### Типы событий (сервер → клиент)

#### `message` — новое сообщение в чате
```json
{
  "type": "message",
  "payload": {
    "id": 1003,
    "chat_id": 101,
    "sender_id": 7,
    "content": "Привет!",
    "type": "text",
    "created_at": "2026-05-02T14:30:00Z"
  }
}
```

#### `typing` — пользователь печатает
```json
{
  "type": "typing",
  "payload": {
    "chat_id": 101,
    "user_id": 7,
    "is_typing": true
  }
}
```

#### `read` — сообщение прочитано
```json
{
  "type": "read",
  "payload": {
    "chat_id": 101,
    "message_id": 1003,
    "user_id": 7
  }
}
```

#### `presence` — изменился статус онлайн
```json
{
  "type": "presence",
  "payload": {
    "user_id": 7,
    "status": "online"
  }
}
```
Допустимые значения `status`: `"online"`, `"offline"`

#### `friend_request` — новая заявка в друзья
```json
{
  "type": "friend_request",
  "payload": {
    "from_user_id": 7,
    "username": "bob"
  }
}
```

#### `room_update` — изменился состав голосовой комнаты
```json
{
  "type": "room_update",
  "payload": {
    "room_id": 1,
    "user_id": 99,
    "username": "new_user",
    "action": "join"
  }
}
```
Допустимые значения `action`: `"join"`, `"leave"`

### Типы событий (клиент → сервер)

#### Инициировать typing indicator
```json
{
  "type": "typing",
  "payload": { "chat_id": 101, "is_typing": true }
}
```

#### Отметить сообщение прочитанным
```json
{
  "type": "read",
  "payload": { "chat_id": 101, "message_id": 1003 }
}
```

---

## 8. Схема базы данных (целевая)

```sql
-- Уже существует (частично)
users (
  id           SERIAL PRIMARY KEY,
  username     VARCHAR(50) UNIQUE NOT NULL,
  password_hash BYTEA NOT NULL,
  created_at   TIMESTAMP DEFAULT NOW(),
  deleted_at   TIMESTAMP
)

friendships (
  user_id    INTEGER REFERENCES users(id),
  friend_id  INTEGER REFERENCES users(id),
  status     VARCHAR(20) NOT NULL,  -- pending | accepted | declined
  created_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (user_id, friend_id)
)

-- Нужно создать (Phase 1.3)
chats (
  id         SERIAL PRIMARY KEY,
  created_at TIMESTAMP DEFAULT NOW()
)

chat_members (
  chat_id  INTEGER REFERENCES chats(id),
  user_id  INTEGER REFERENCES users(id),
  PRIMARY KEY (chat_id, user_id)
)

messages (
  id          SERIAL PRIMARY KEY,
  chat_id     INTEGER REFERENCES chats(id),
  sender_id   INTEGER REFERENCES users(id),
  content     TEXT NOT NULL,
  type        VARCHAR(20) DEFAULT 'text',
  reply_to_id INTEGER REFERENCES messages(id),  -- Phase 2
  created_at  TIMESTAMP DEFAULT NOW(),
  edited_at   TIMESTAMP,
  deleted_at  TIMESTAMP
)

-- Phase 3
voice_rooms (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  created_by INTEGER REFERENCES users(id),
  is_active  BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
)

room_members (
  room_id   INTEGER REFERENCES voice_rooms(id),
  user_id   INTEGER REFERENCES users(id),
  is_muted  BOOLEAN DEFAULT FALSE,
  joined_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (room_id, user_id)
)

-- Phase 2
reactions (
  message_id INTEGER REFERENCES messages(id),
  user_id    INTEGER REFERENCES users(id),
  emoji      VARCHAR(10) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id, emoji)
)

read_status (
  message_id INTEGER REFERENCES messages(id),
  user_id    INTEGER REFERENCES users(id),
  read_at    TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
)
```

---

## 9. Сводная таблица эндпоинтов

| Метод | Path | Auth | Статус |
|---|---|---|---|
| `POST` | `/auth/register` | ❌ | ✅ Реализовано |
| `POST` | `/auth/login` | ❌ | ✅ Реализовано |
| `GET` | `/user/search?q=` | ❌ | ✅ Реализовано |
| `GET` | `/user/username/:username` | ❌ | ✅ Реализовано |
| `GET` | `/user/:id` | ❌ | ✅ Реализовано |
| `POST` | `/friendship/` | ✅ | ✅ Реализовано |
| `GET` | `/friendship/pending?user_id=` | ✅ | ✅ Реализовано |
| `GET` | `/friendship/pending/count?user_id=` | ✅ | ✅ Реализовано |
| `PATCH` | `/friendship/:user_id/status` | ✅ | ❌ Нужно сделать |
| `GET` | `/friendship/friends?user_id=` | ✅ | ❌ Нужно сделать |
| `GET` | `/chat/` | ✅ | ❌ Нужно сделать |
| `POST` | `/chat/` | ✅ | ❌ Нужно сделать |
| `GET` | `/chat/:id/messages` | ✅ | ❌ Нужно сделать |
| `POST` | `/chat/:id/messages` | ✅ | ❌ Нужно сделать |
| `GET` | `/voice-room/` | ✅ | ❌ Нужно сделать |
| `POST` | `/voice-room/` | ✅ | ❌ Нужно сделать |
| `POST` | `/voice-room/:id/join` | ✅ | ❌ Нужно сделать |
| `POST` | `/voice-room/:id/leave` | ✅ | ❌ Нужно сделать |
| `GET` | `/ws?token=` | (в URL) | ❌ Нужно сделать |

**Итого:** 8 реализовано, 11 нужно сделать.
