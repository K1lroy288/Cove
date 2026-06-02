# План: Доработка Cove до уровня продакшн-мессенджера

## Контекст

Cove находится в хорошем MVP-состоянии: бэкенд реализован примерно на 85% (все эндпоинты для Phase 1–3 есть), фронтенд — на ~65%. Цель — довести до уровня Telegram по качеству: надёжность, UX-полировка, безопасность. Голосовые комнаты исключены из скоупа.

**Ключевые находки аудита:**

### Критические дефекты (сейчас сломаны)
- **[Frontend]** Токен хранится только в памяти (`AuthNotifier`) — при перезапуске приложения пользователь теряет сессию. Нет `flutter_secure_storage`.
- **[Frontend]** Пагинация сообщений не реализована — `_loadMessages()` загружает только последние 50 сообщений и не подгружает историю при скролле вверх.
- **[Backend]** Нет валидации длин строк — любой ввод принимается (username, сообщения, название группы и т.д.).

### Безопасность
- **[Backend]** WebSocket: `CheckOrigin` возвращает `true` для всех origin'ов — CORS-уязвимость.
- **[Backend]** Нет rate limiting на login, register, message send, search.
- **[Backend]** Мягко удалённые пользователи (`deleted_at IS NULL` не везде) появляются в поиске.
- **[Backend]** JWT secret не валидируется на минимальную длину при старте.

### UX-дефекты (мешают ощущению продакшн-продукта)
- Нет состояний загрузки (skeleton loaders) в списке чатов и сообщений.
- Нет empty states: пустой список друзей, пустой чат.
- WebSocket реконнект — фиксированные 3 сек без экспоненциального бэкоффа.
- Нет индикатора состояния соединения (offline/reconnecting).
- Нет pull-to-refresh в списке чатов и друзей.
- Набранный текст (drafts) хранится только в `_drafts` map виджета — теряется при смене экрана.
- Нет визуальной анимации typing-indicator (только текст).
- Нет прокрутки к оригинальному сообщению при тапе на reply.
- Pinned message banner не показывается в шапке чата.

### Неполные фичи
- **[Frontend]** UI пересылки сообщений (forward) отсутствует, хотя бэкенд поддерживает.
- **[Frontend]** Предпросмотр ссылок (link preview) отсутствует.
- **[Frontend]** Выбор нескольких сообщений для удаления/пересылки.
- **[Backend]** Миграция 011 дублирует 008 (оба добавляют `avatar_url`).
- **[Backend]** `User.Settings` JSONB-поле в модели `users` не используется (есть отдельная таблица `user_settings`).

---

## Фазы реализации

### Фаза 1 — Критические исправления (2–3 дня)

#### 1.1 Персистентность токена [Flutter]
**Файлы:** `frontend/pubspec.yaml`, `frontend/lib/features/auth/presentation/auth_notifier.dart`

- Добавить зависимость `flutter_secure_storage: ^9.x`
- В `AuthNotifier.login()` сохранять token/userId/username через `FlutterSecureStorage`
- В `AuthNotifier` добавить метод `tryRestoreSession()` — читает из secure storage и вызывает `login()` при наличии
- В `main.dart` вызвать `tryRestoreSession()` перед `runApp`, при наличии сессии — сразу подключать WS
- В `AuthNotifier.logout()` — очищать secure storage

#### 1.2 Пагинация сообщений [Flutter]
**Файлы:** `frontend/lib/features/chat/presentation/widgets/chat_window_panel.dart`

- Добавить `_hasMore = true`, `_isLoadingMore = false`
- Прикрепить listener к `_scrollController`: при `position.pixels >= maxScrollExtent - 200` вызывать `_loadMoreMessages()`
- `_loadMoreMessages()` передаёт `before: _messages.first.id` в `ChatService.getMessages()`
- Результат prepend в `_messages`, не прокручивать к низу
- Если вернулось < 50 сообщений — `_hasMore = false`
- Показывать `CircularProgressIndicator` сверху списка при `_isLoadingMore`

#### 1.3 Валидация входных данных на бэкенде [Go]
**Файлы:** `backend/internal/DTO/` (все файлы запросов), `backend/internal/service/`

- Добавить binding-теги к DTO: `binding:"required,min=3,max=32"` для username; `binding:"required,min=8,max=72"` для password; `binding:"required,max=10000"` для message content; `binding:"required,min=1,max=100"` для group names; `max=500` для bio
- В хендлерах использовать `c.ShouldBindJSON(&req)` вместо ручного парсинга (уже используется, нужно добавить теги)
- Возвращать `400` с readable сообщением об ошибке при провале валидации

---

### Фаза 2 — Безопасность (2–3 дня)

#### 2.1 Rate limiting [Go]
**Файлы:** новый `backend/internal/middleware/rate_limit.go`, `backend/cmd/main.go`

- Использовать `golang.org/x/time/rate` или `github.com/ulule/limiter`
- Лимиты: login/register — 10/min per IP; send message — 60/min per user; search — 30/min per IP
- Middleware возвращает `429 Too Many Requests` с `Retry-After` заголовком
- Подключить в `main.go` к нужным группам роутов

#### 2.2 WebSocket CORS [Go]
**Файл:** `backend/internal/handler/app_hub.go` (или где `upgrader` определён)

- Изменить `upgrader.CheckOrigin` с `return true` на проверку `Origin` заголовка против `AppConfig.AllowedOrigins`
- Добавить `ALLOWED_ORIGINS` в config

#### 2.3 Soft-delete в user queries [Go]
**Файл:** `backend/internal/repository/user_repository.go`

- Добавить `.Where("deleted_at IS NULL")` или `.Unscoped(false)` в `GetUserByID`, `GetUserByUsername`, поиск пользователей
- Проверить все места где используются user queries

#### 2.4 Очистка: убрать дубликат миграции и неиспользуемое поле [Go]
**Файлы:** `backend/internal/db/migration/017_remove_users_settings_column.{up,down}.sql`

- Создать миграцию 017, убирающую неиспользуемый `settings` JSONB column из таблицы `users`
- Обновить `backend/internal/model/user.go` — убрать поле `Settings`

---

### Фаза 3 — UX-полировка (5–7 дней)

#### 3.1 Skeleton loaders и empty states [Flutter]

**Chat list** (`chat_list_panel.dart`):
- При `_isLoading` показывать 6 skeleton-карточек (серые прямоугольники с shimmer эффектом или просто контейнеры с анимацией opacity)
- Empty state: иконка + "Начните разговор — найдите друга через поиск"

**Chat window** (`chat_window_panel.dart`):
- При `_isLoading` показывать skeleton сообщений (3–5 пузырей)
- Empty state: "Напишите первое сообщение"

**Friends panel** (`friends_panel.dart`):
- Empty state уже есть, проверить корректность

#### 3.2 Индикатор соединения [Flutter]
**Файлы:** `notification_notifier.dart`, `main_screen.dart`

- В `NotificationNotifier` добавить `ConnectionState` enum: `connected | connecting | disconnected`
- При `onDone` / `onError` переходить в `disconnected` → `connecting` при реконнекте
- При успешном подключении → `connected`
- В `MainScreen` показывать тонкий баннер снизу при `disconnected`/`connecting`: "Нет соединения" / "Подключение..."

#### 3.3 Экспоненциальный бэкофф для WS реконнекта [Flutter]
**Файл:** `notification_notifier.dart`

- Заменить фиксированный `Future.delayed(3s)` на экспоненциальный бэкофф: 1s → 2s → 4s → 8s → 16s → max 30s
- Сбрасывать счётчик при успешном подключении

#### 3.4 Pull-to-refresh [Flutter]
**Файлы:** `chat_list_panel.dart`, `friends_panel.dart`

- Обернуть списки в `RefreshIndicator`
- При pull вызывать `_loadChats()` / `_loadFriends()`

#### 3.5 Прокрутка к оригиналу при тапе на reply [Flutter]
**Файл:** `chat_window_panel.dart`

- При тапе на reply-block в сообщении — найти индекс оригинала в `_messages` по `repliedTo.id`
- Если найден — `_scrollController.animateTo(index)` (для `ListView.builder` использовать `Scrollable.ensureVisible` или рассчитать offset)
- Если не найден — загрузить историю до этого сообщения (опционально)

#### 3.6 Анимация typing indicator [Flutter]
**Файл:** `chat_window_panel.dart`

- Заменить текст `_typingUsers.values.join(', ') + ' печатает...'` на animated dots виджет (три точки с AnimationController)
- Добавить `AnimatedSwitcher` для появления/исчезновения

#### 3.7 Pinned message banner [Flutter]
**Файл:** `chat_window_panel.dart`

- `_localPinnedMessage` уже есть в стейте
- Показывать `AnimatedContainer` под AppBar с иконкой 📌, именем отправителя и кратким текстом сообщения
- Тап — скроллим к закреплённому сообщению (если есть в `_messages`)
- Крестик (для админов) — вызывает `unpinMessage`

#### 3.8 Индикатор онлайн в шапке чата [Flutter]
**Файл:** `chat_window_panel.dart`

- Для DM-чата показывать под именем: "онлайн" (зелёный dot) или "был(а) N минут назад"
- Данные берём из `NotificationNotifier.isOnline(partnerId)` и профиля (lastSeenAt)

---

### Фаза 4 — Недостающие фичи (3–5 дней)

#### 4.1 Пересылка сообщений (Forward) [Flutter]
**Файл:** `chat_window_panel.dart`, `chat_service.dart`

- В контекстном меню сообщения добавить "Переслать"
- Показывать bottom sheet со списком чатов для выбора получателя
- Вызывать `ChatService.sendMessage()` с `forwardedFromId` и `forwardedFromUsername`
- Отображать forwarded-header в message bubble (уже есть данные в модели, нужен UI)

#### 4.2 Выбор нескольких сообщений [Flutter]
**Файл:** `chat_window_panel.dart`

- Long press на сообщение → входим в режим выбора (`_selectionMode = true`, `_selectedIds = Set<int>`)
- AppBar меняется: показывает кол-во выбранных + кнопки "Удалить", "Переслать"
- Тап на сообщение в режиме выбора — добавляет/убирает из сета
- Массовое удаление: API не поддерживает batch delete, вызываем по одному (или добавить эндпоинт)

#### 4.3 Предпросмотр ссылок [Flutter]
**Файлы:** `chat_window_panel.dart` или отдельный `link_preview_widget.dart`

- При отправке сообщения парсим URL regex
- Если URL найден — показываем превью карточку над полем ввода (og:title, og:image, og:description)
- Для получения og-данных — простой GET запрос через backend proxy или напрямую
- В bubble сообщения с URL показываем компактную карточку превью под текстом
- **Примечание:** это опциональная фича, реализуем если есть время

#### 4.4 Улучшения в профиле и настройках [Flutter]

- Кнопка "Копировать username" в профиле
- В настройках: показывать текущий username кликабельным
- В GroupInfoSheet: показывать badge онлайн у каждого участника

---

## Порядок реализации

```
Фаза 1.1: Token persistence          ← Самое важное, без этого UX сломан
Фаза 1.2: Message pagination         ← Второе по важности
Фаза 1.3: Backend validation         ← Безопасность/стабильность
Фаза 2.1: Rate limiting             ← Security
Фаза 2.2: WS CORS                   ← Security
Фаза 2.3: Soft-delete fix           ← Bug fix
Фаза 2.4: DB cleanup                ← Hygiene
Фаза 3.1: Skeletons & empty states  ← UX ощущение
Фаза 3.2: Connection indicator       ← UX ощущение
Фаза 3.3: WS backoff                ← Stability
Фаза 3.4: Pull-to-refresh           ← UX
Фаза 3.5: Reply scroll              ← UX
Фаза 3.6: Typing animation          ← UX polish
Фаза 3.7: Pinned banner             ← Completeness
Фаза 3.8: Online indicator          ← UX
Фаза 4.1: Forward UI               ← Feature completeness
Фаза 4.2: Multi-select             ← Feature completeness
Фаза 4.3: Link preview             ← Nice to have
Фаза 4.4: Profile polish           ← Polish
```

---

## Критические файлы

### Backend
- `backend/cmd/main.go` — роутинг, подключение middleware
- `backend/internal/DTO/` — все файлы (добавить binding теги)
- `backend/internal/middleware/rate_limit.go` — новый файл
- `backend/internal/handler/app_hub.go` — WS CORS
- `backend/internal/repository/user_repository.go` — soft-delete
- `backend/internal/model/user.go` — убрать Settings поле
- `backend/internal/db/migration/017_*` — новый файл

### Frontend
- `frontend/pubspec.yaml` — добавить flutter_secure_storage
- `frontend/lib/features/auth/presentation/auth_notifier.dart` — token persistence
- `frontend/lib/main.dart` — restore session on startup
- `frontend/lib/features/chat/presentation/widgets/chat_window_panel.dart` — пагинация, typing animation, pinned banner, reply scroll
- `frontend/lib/features/chat/presentation/notification_notifier.dart` — connection state, backoff
- `frontend/lib/features/chat/presentation/widgets/chat_list_panel.dart` — skeleton, pull-to-refresh
- `frontend/lib/features/friends/presentation/widgets/friends_panel.dart` — pull-to-refresh
- `frontend/lib/features/chat/presentation/main_screen.dart` — connection banner

---

## Верификация

1. **Token persistence**: Войти, закрыть/открыть приложение → должен сразу попасть в чат без логина
2. **Message pagination**: Открыть чат с >50 сообщениями, скроллить вверх → история подгружается
3. **Validation**: Отправить пустое имя пользователя при регистрации → 400 с понятной ошибкой
4. **Rate limiting**: 11 попыток логина за минуту → 429
5. **WS reconnect**: Отключить сервер, подождать → индикатор "нет соединения"; включить → реконнект с backoff, статус меняется на "connected"
6. **Pull-to-refresh**: Потянуть список чатов → обновляется
7. **Pinned message**: Закрепить сообщение в группе → banner появляется; тап — скроллит к сообщению
8. **Forward**: Выбрать "Переслать" в меню сообщения → выбрать чат → сообщение появляется у получателя с forwarded-header
