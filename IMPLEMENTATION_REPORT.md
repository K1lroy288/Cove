# Отчёт о реализации: Production-hardening Cove

## Сводная таблица: план vs реализация

| # | Пункт из PLAN.md | Статус | Примечание |
|---|---|---|---|
| 1.1 | Token persistence | ✅ Реализовано | `flutter_secure_storage` в `AuthNotifier` |
| 1.2 | Message pagination | ✅ Реализовано | Cursor-based, scroll listener |
| 1.3 | Backend validation | ✅ Реализовано | Binding-теги на всех DTO |
| 2.1 | Rate limiting | ✅ Реализовано | IP-лимитер + user-лимитер |
| 2.2 | WebSocket CORS | ✅ Реализовано | `AllowedOrigins` с wildcard |
| 2.3 | Soft-delete fix | ✅ Реализовано | `GetUserById` с `First()` |
| 2.4 | DB cleanup | ✅ Реализовано | Миграция 017 + модель |
| 3.1 | Skeleton loaders | ✅ Реализовано | `_SkeletonBox` с opacity animation |
| 3.1 | Empty states | ✅ Уже было | Были до реализации |
| 3.2 | Индикатор соединения | ✅ Реализовано | Баннер в `MainScreen` |
| 3.3 | WS exponential backoff | ✅ Реализовано | 1→2→4→8→16→30s |
| 3.4 | Pull-to-refresh | ✅ Уже было | `RefreshIndicator` был |
| 3.5 | Reply scroll | ✅ Реализовано | `_scrollToMessage()` |
| 3.6 | Typing animation | ✅ Уже было | `_TypingDots` был |
| 3.7 | Pinned message banner | ✅ Уже было | `_buildPinBanner()` был |
| 3.8 | Online indicator | ✅ Частично | "В сети" было; добавлен "был(а) N мин назад" |
| 4.1 | Forward UI | ✅ Уже было | `_showForwardSheet` был |
| 4.2 | Multi-select | ✅ Реализовано | `_selectionMode` + `_selectedMessageIds` |
| 4.3 | Link preview | ❌ Не реализовано | Опциональная фича, не сделана |
| 4.4 | Profile polish | ❌ Не реализовано | Копировать username и т.д. |

---

## Детальное описание каждого изменения

---

### 1.1 Персистентность токена

**Файлы изменены:**
- `frontend/pubspec.yaml` — добавлена зависимость `flutter_secure_storage`
- `frontend/lib/features/auth/presentation/auth_notifier.dart` — полностью переписан
- `frontend/lib/main.dart` — добавлен вызов `tryRestoreSession()` и `_SplashScreen`

**Что именно сделано:**

`AuthNotifier` теперь использует `FlutterSecureStorage` с тремя ключами: `auth_token`, `auth_user_id`, `auth_username`.

- `login()` — сохраняет все три значения в secure storage после обновления стейта
- `logout()` — вызывает `_storage.deleteAll()` для полной очистки
- `tryRestoreSession()` — читает из storage, если данные есть — вызывает внутренний login
- `updateUsername()` — обновляет `auth_username` в storage при смене имени
- Добавлено поле `isRestoring = true` — пока идёт восстановление, UI показывает splash-screen

В `main.dart`:
```dart
await authNotifier.tryRestoreSession();
```
Это вызывается **до** `runApp`, поэтому к моменту первого рендера состояние уже известно. `Consumer<AuthNotifier>` показывает `_SplashScreen` пока `isRestoring == true`.

**Ключевой момент:** listener `authNotifier.addListener(...)` срабатывает на `tryRestoreSession()` — WS подключается автоматически при восстановленной сессии.

---

### 1.2 Пагинация сообщений

**Файлы изменены:**
- `frontend/lib/features/chat/presentation/widgets/chat_window_panel.dart`

**Что именно сделано:**

Добавлены поля:
```dart
bool _isLoadingMore = false;
bool _hasMore = true;
```

В `initState()` добавлен слушатель на скролл:
```dart
_scrollController.addListener(_onScroll);
```

`_onScroll()` — срабатывает когда `position.pixels <= 200` (т.е. пользователь проскроллил близко к самому верху списка). Вызывает `_loadMoreMessages()` только если `!_isLoadingMore && _hasMore && !_isLoading`.

`_loadMoreMessages()`:
1. Берёт ID самого старого сообщения: `_messages.first.id`
2. Запрашивает `ChatService.getMessages(before: beforeId)`
3. Prepend'ит результат в начало `_messages` (сортировка по id)
4. Если вернулось < 50 — ставит `_hasMore = false`

В `_buildMessageList()`:
- При `_isLoadingMore == true` показывает маленький `CircularProgressIndicator` как первый элемент ListView
- При `_hasMore == true` резервирует слот под индикатор (`extraItem = 1`), но показывает `SizedBox.shrink()` пока не грузит

При смене чата (`didUpdateWidget`) — сбрасываются `_isLoadingMore`, `_hasMore = true`.
В `_loadMessages()` — `_hasMore = msgs.length >= 50`.

---

### 1.3 Валидация входных данных на бэкенде

**Файлы изменены:**
- `backend/internal/DTO/user.go`
- `backend/internal/DTO/message.go`
- `backend/internal/DTO/friendship.go`
- `backend/internal/DTO/chat.go`

**Что именно добавлено:**

`user.go`:
```go
// Регистрация/логин
Username string `binding:"required,min=3,max=32"`
Password string `binding:"required,min=8,max=72"`

// Обновление профиля
Username  *string `binding:"omitempty,min=3,max=32"`
Bio       *string `binding:"omitempty,max=500"`
AvatarURL *string `binding:"omitempty,max=512"`

// Смена пароля
CurrentPassword string `binding:"required,min=1"`
NewPassword     string `binding:"required,min=8,max=72"`
```

`message.go`:
```go
Content               string  `binding:"required,max=10000"`
Type                  string  `binding:"omitempty,oneof=text image video audio file"`
FileName              *string `binding:"omitempty,max=255"`
Caption               *string `binding:"omitempty,max=5000"`
ForwardedFromUsername *string `binding:"omitempty,max=32"`
// Edit:
Content string `binding:"required,min=1,max=10000"`
```

`friendship.go`:
```go
Status string `binding:"required,oneof=accepted declined"`
```

`chat.go`:
```go
Name   *string `binding:"omitempty,min=1,max=100"`
Avatar *string `binding:"omitempty,max=512"`
```

Хендлеры уже используют `c.ShouldBindJSON()` и возвращают `400` при ошибке валидации — изменений в хендлерах не потребовалось.

---

### 2.1 Rate Limiting

**Файлы изменены/созданы:**
- `backend/internal/middleware/rate_limit.go` — новый файл
- `backend/cmd/main.go` — подключение
- `backend/go.mod` / `go.sum` — добавлен `golang.org/x/time`

**Реализация:**

Два типа лимитеров:

`RateLimiter` — per IP. Хранит `map[string]*ipLimiter` с cleanup goroutine (удаляет записи старше 10 минут каждые 5 минут).

`userRateLimiter` — per user_id из JWT-контекста. Аналогичная структура с `map[uint]*ipLimiter`.

Оба используют `golang.org/x/time/rate` — token bucket алгоритм.

**Подключённые лимиты:**
```go
authLimiter  := NewRateLimiter(10.0/60, 15)    // 10 req/min per IP, burst 15
searchLimiter := NewRateLimiter(30.0/60, 10)   // 30 req/min per IP, burst 10
msgLimiter   := NewUserRateLimiter(60.0/60, 20) // 60 msg/min per user, burst 20
```

- `auth.Use(authLimiter.Middleware())` — весь `/auth` роут (login + register)
- `user.GET("/search", searchLimiter.Middleware(), ...)` — только поиск
- `chat.POST("/:id/messages", msgLimiter.Middleware(), ...)` — только отправка сообщений

При превышении → `429 Too Many Requests` с заголовком `Retry-After: 60`.

---

### 2.2 WebSocket CORS

**Файлы изменены:**
- `backend/internal/handler/app_hub.go`
- `backend/internal/config/config.go`

**Что изменено:**

В `config.go` добавлено поле:
```go
AllowedOrigins []string
```
Парсится из env `ALLOWED_ORIGINS` (comma-separated). По умолчанию: `"http://localhost:*,http://127.0.0.1:*"`.

В `app_hub.go` функция `CheckOrigin` заменена на:
```go
CheckOrigin: func(r *http.Request) bool {
    origin := r.Header.Get("Origin")
    if origin == "" { return true }  // нативные клиенты без Origin
    for _, pattern := range config.GetConfig().AllowedOrigins {
        matched, _ := path.Match(strings.ToLower(pattern), strings.ToLower(origin))
        if matched { return true }
    }
    log.Printf("ws: rejected origin %q", origin)
    return false
},
```

В продакшне нужно задать: `ALLOWED_ORIGINS=https://your-domain.com`.

---

### 2.3 Soft-delete fix

**Файлы изменены:**
- `backend/internal/repository/user_repository.go`

**Что исправлено:**

`GetUserById` был написан как:
```go
r.DB.Model(&model.User{ID: id}).Scan(&user)  // НЕ применяет soft-delete фильтр
```

Исправлено на:
```go
r.DB.Where("id = ?", id).First(&user)  // GORM автоматически добавляет AND deleted_at IS NULL
```

`GetUserByUsername` использовал `First()` — уже корректно, т.к. модель `User` embed'ит `gorm.Model` с `DeletedAt gorm.DeletedAt`, GORM автоматически фильтрует мягко-удалённых.

---

### 2.4 DB cleanup

**Файлы изменены/созданы:**
- `backend/internal/db/migration/017_remove_users_settings_column.up.sql`
- `backend/internal/db/migration/017_remove_users_settings_column.down.sql`
- `backend/internal/model/user.go`

**up.sql:**
```sql
ALTER TABLE users DROP COLUMN IF EXISTS settings;
```

**down.sql:**
```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS settings jsonb;
```

В модели убрано поле `Settings datatypes.JSON` и импорт `"gorm.io/datatypes"`.

---

### 3.1 Skeleton loaders

**Файлы изменены:**
- `frontend/lib/features/chat/presentation/widgets/chat_list_panel.dart`

**Что сделано:**

Добавлен виджет `_SkeletonBox` в конец файла — StatefulWidget с `AnimationController`, `Tween<double>(0.3, 0.7)`, `Curves.easeInOut`. Анимирует `opacity` контейнера.

Добавлен метод `_buildSkeletonList()` — рисует 7 skeleton-строк в форме `Row(circle + 2 lines + timestamp)`, используя `_SkeletonBox` с `colors.surface` в качестве цвета.

`_buildChatList()` теперь при `_isLoadingChats == true` показывает `_buildSkeletonList()` вместо `CircularProgressIndicator`.

---

### 3.2 + 3.3 Индикатор соединения + Exponential backoff

**Файлы изменены:**
- `frontend/lib/features/chat/presentation/notification_notifier.dart`
- `frontend/lib/features/chat/presentation/main_screen.dart`

**В `notification_notifier.dart`:**

Добавлен enum:
```dart
enum WsConnectionState { connected, connecting, disconnected }
```

Поля:
```dart
WsConnectionState _connectionState = WsConnectionState.disconnected;
int _reconnectAttempt = 0;
```

Метод `_subscribe()` теперь:
1. Переходит в `connecting` при запуске
2. При первом получении любого события — переходит в `connected`, сбрасывает `_reconnectAttempt = 0`
3. При `onError` / `onDone` — вызывает `_scheduleReconnect()`

`_scheduleReconnect()`:
```dart
final delay = Duration(seconds: (1 << _reconnectAttempt).clamp(1, 30));
_reconnectAttempt = (_reconnectAttempt + 1).clamp(0, 5);
```
Задержки: 1s, 2s, 4s, 8s, 16s, 30s (при attempt=5 → `1<<5=32` → clamp до 30).

`connect()` и `disconnect()` сбрасывают `_reconnectAttempt = 0`.

**В `main_screen.dart`:**

Добавлен метод `_buildConnectionBanner(WsConnectionState state)` — при `connected` возвращает `SizedBox.shrink()`. При `disconnected` — красный баннер 28px с иконкой `wifi_off`. При `connecting` — оранжевый баннер с маленьким `CircularProgressIndicator`.

Баннер добавлен в Column Scaffold после `_buildPersistentCallBar`.

---

### 3.5 Прокрутка к оригинальному сообщению при тапе на reply

**Файлы изменены:**
- `frontend/lib/features/chat/presentation/widgets/chat_window_panel.dart`

**Что сделано:**

Добавлен метод `_scrollToMessage(int messageId)`:
- Находит индекс сообщения в `_messages`
- Учитывает offset за `extraItem` (индикатор загрузки)
- Рассчитывает приблизительный offset: `idx * 80.0` (т.к. `ListView.builder` без `itemExtent`)
- Clamp'ит до `maxScrollExtent`
- Вызывает `animateTo` с `Curves.easeOut`, 350ms

`_buildReplyQuote()` обёрнут в `GestureDetector(onTap: () => _scrollToMessage(reply.id), ...)`.

**Ограничение:** offset рассчитан приблизительно (80px на сообщение). Если сообщения сильно отличаются по высоте — скролл может не попасть точно. Точный расчёт требует GlobalKey на каждый элемент, что дорого по памяти. Для большинства случаев работает достаточно точно.

---

### 3.8 Онлайн-индикатор: "был(а) N мин назад"

**Файлы изменены:**
- `frontend/lib/features/chat/presentation/widgets/chat_window_panel.dart`

**Что уже было:** "В сети" (зелёный текст) при `isOnline(chat.partnerId) == true`.

**Что добавлено:**

Поле `DateTime? _partnerLastSeen` в стейте.

В `_loadMessages()` для DM-чатов — запрос профиля партнёра:
```dart
final profile = await _userService.getUserProfile(widget.chat.partnerId, auth.token!);
if (mounted && profile != null) setState(() => _partnerLastSeen = profile.lastSeenAt);
```

Метод `_formatLastSeen(DateTime dt)`:
- < 1 мин → "был(а) только что"
- < 60 мин → "был(а) N мин назад"
- < 24 ч → "был(а) N ч назад"
- < 7 дней → "был(а) N д назад"
- иначе → "был(а) дд.мм.гггг"

В шапке чата (только для DM) показывается, если `isOnline == false` И `_partnerLastSeen != null`.

---

### 4.2 Multi-select сообщений

**Файлы изменены:**
- `frontend/lib/features/chat/presentation/widgets/chat_window_panel.dart`

**Что добавлено:**

Поля:
```dart
bool _selectionMode = false;
final Set<int> _selectedMessageIds = {};
```

**Поведение:**
- **Long press** на сообщение (когда `_selectionMode == false`) → входит в режим выбора + добавляет это сообщение в `_selectedMessageIds`
- **Long press** когда уже в режиме выбора → открывает обычное контекстное меню
- **Tap** на сообщение в режиме выбора → toggle: добавляет/убирает из Set. Если Set стал пустым — выходит из режима
- **Right-click** (secondary tap) — всегда открывает контекстное меню (для desktop)
- Выбранное сообщение подсвечивается `AnimatedContainer` с `accentIndigo` opacity 0.12

Метод `_buildSelectionHeader()` — рендерит вместо обычного `_buildHeader()` при `_selectionMode == true`:
- Кнопка "X" — выход из режима (сбрасывает `_selectionMode`, очищает Set)
- "Выбрано: N"
- Кнопка "Переслать" (forward) — пересылает первое выбранное сообщение (через `_showForwardSheet`)
- Кнопка "Удалить" — вызывает `_deleteSelectedMessages()`

`_deleteSelectedMessages()`:
1. Диалог подтверждения с кол-вом сообщений
2. Сбрасывает selection mode
3. Итерирует по IDs, вызывает `_api.deleteMessage()` по одному
4. При успехе — помечает сообщение как deleted в `_messages`

---

## Что НЕ было реализовано из PLAN.md

| Пункт | Причина |
|---|---|
| 4.3 Link preview | Помечено как "опциональная фича" в плане, не хватило времени |
| 4.4 Profile polish (копировать username, badge online в группе) | Низкий приоритет, not implemented |
| JWT secret validation at startup | Упомянуто в аудите, не вошло в фазы плана |

---

## Детальная инструкция по тестированию

### Предварительные условия

```bash
# Запуск базы данных
cd /home/ku/cove
docker compose -f backend/deployments/docker-compose.yml up -d

# Запуск бэкенда
cd backend && go run ./cmd/main.go
# Сервер на порту 3425

# Запуск фронтенда
cd ../frontend && flutter run -d linux
# или -d chrome / -d windows
```

---

### Тест 1.1 — Персистентность токена

**Цель:** Убедиться, что сессия сохраняется после перезапуска.

1. Откройте приложение → появится экран логина (или splash, затем чат если уже залогинены)
2. Войдите в аккаунт
3. Убедитесь, что попали на главный экран с чатами
4. **Полностью закройте приложение** (не свернуть, а закрыть процесс)
5. Запустите приложение снова
6. **Ожидаемый результат:** Кратковременный spinner (splash), затем сразу главный экран — без экрана логина
7. **Проверка выхода:** Зайдите в настройки → "Выйти из аккаунта" → закройте и откройте снова → должен показаться экран логина

**Что проверяет:** `AuthNotifier.tryRestoreSession()` + `FlutterSecureStorage` чтение при старте.

---

### Тест 1.2 — Пагинация сообщений

**Цель:** История загружается при скролле вверх.

1. Найдите чат, в котором **более 50 сообщений**
2. Откройте чат — загрузятся последние 50 сообщений
3. Медленно скрольте вверх к самому первому видимому сообщению
4. **Ожидаемый результат:** При достижении верха появится маленький spinner сверху списка, затем подгрузится пачка более старых сообщений
5. Продолжайте скроллить — повторяется до тех пор, пока не загрузятся все сообщения (тогда spinner пропадёт)

**Граничный случай:** Если в чате менее 50 сообщений — spinner не появится совсем (флаг `_hasMore = false` сразу).

---

### Тест 1.3 — Валидация на бэкенде

**Цель:** Сервер отклоняет невалидный ввод с понятной ошибкой.

```bash
# Регистрация с коротким именем (< 3 символов)
curl -X POST http://localhost:3425/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"ab","password":"password123"}'
# Ожидается: 400 Bad Request, {"message":"Неверный формат данных"}

# Регистрация с коротким паролем (< 8 символов)
curl -X POST http://localhost:3425/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"validname","password":"short"}'
# Ожидается: 400

# Слишком длинный контент сообщения (> 10000 символов)
TOKEN="ваш_токен"
LONG=$(python3 -c "print('a'*10001)")
curl -X POST http://localhost:3425/chat/1/messages \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"content\":\"$LONG\",\"type\":\"text\"}"
# Ожидается: 400

# Невалидный статус дружбы
curl -X PATCH http://localhost:3425/friendship/2/status \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"status":"maybe"}'
# Ожидается: 400 (только "accepted" или "declined" допустимы)
```

---

### Тест 2.1 — Rate Limiting

**Цель:** После превышения лимита сервер возвращает 429.

```bash
# Сделать 12 попыток логина за несколько секунд (лимит 10/мин per IP)
for i in $(seq 1 12); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -X POST http://localhost:3425/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"test","password":"wrongpass"}'
done
# Первые 10-15 запросов: 401 (неверный пароль)
# После превышения бёрста: 429 Too Many Requests

# Проверка заголовка
curl -v -X POST http://localhost:3425/auth/login ... 2>&1 | grep -i "retry-after"
# Ожидается: Retry-After: 60
```

---

### Тест 2.2 — WebSocket CORS

**Цель:** WS соединения с неизвестных origin'ов отклоняются.

```bash
# Попытка подключения с посторонним origin (должна быть отклонена)
# В браузерной консоли:
# new WebSocket('ws://localhost:3425/ws?token=YOUR_TOKEN')
# При запуске с http://evil.com → должен быть rejected

# Проверка логов сервера — должна появиться строка:
# ws: rejected origin "http://unknown-origin.com"
```

**Для нативного Flutter приложения** (Linux/Windows) — origin пустой, всегда разрешается. Это корректное поведение.

В продакшне добавить в `.env`:
```
ALLOWED_ORIGINS=https://your-app-domain.com
```

---

### Тест 2.3 — Soft-delete

**Цель:** Удалённые пользователи не появляются в поиске и не доступны по ID.

```bash
TOKEN="токен_пользователя_alice"
ALICE_ID=1  # ID пользователя

# 1. Удалить аккаунт alice
curl -X DELETE http://localhost:3425/user/me \
  -H "Authorization: Bearer $TOKEN"
# 200 OK

# 2. Попытаться найти alice по ID
curl http://localhost:3425/user/$ALICE_ID
# Ожидается: 404 Not Found (а не данные пользователя)

# 3. Попытаться найти alice по username
curl "http://localhost:3425/user/search?q=alice"
# Ожидается: 404 Not Found
```

---

### Тест 2.4 — Миграция 017

**Цель:** Поле `settings` удалено из таблицы `users`.

```bash
# Подключиться к БД
docker exec -it $(docker ps -q -f name=postgres) psql -U postgres -d cove

# Проверить структуру таблицы
\d users
# Столбца "settings" быть не должно

# Миграция применяется автоматически при запуске бэкенда
# Проверить номер последней миграции:
SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 3;
# Должна быть строка с "17"
```

---

### Тест 3.1 — Skeleton Loaders

**Цель:** При загрузке чатов видны анимированные заглушки вместо спиннера.

1. **Замедлите сеть** (в браузере: DevTools → Network → Slow 3G) или замедлите бэкенд (добавьте `time.Sleep` в handler) 
2. Перейдите на вкладку "Чаты"
3. **Ожидаемый результат:** 7 анимированных строк с пульсирующим opacity (gray rectangle вместо аватара + 2 серые полоски)
4. После загрузки — список реальных чатов

---

### Тест 3.2 + 3.3 — Индикатор соединения + Backoff

**Цель:** При потере соединения показывается баннер и реконнект идёт с backoff.

1. Войдите в приложение, убедитесь что нет баннера (всё подключено)
2. **Остановите бэкенд:** `Ctrl+C` в терминале с сервером
3. **Ожидаемый результат через ~1с:** Снизу появится красный баннер "Нет соединения" с иконкой `wifi_off`
4. **Запустите бэкенд снова:** `go run ./cmd/main.go`
5. **Ожидаемый результат:** Баннер сменится на оранжевый "Подключение..." (со спиннером), затем пропадёт совсем

**Проверка backoff через логи Flutter** (консоль):
```
ws reconnecting in 1s (attempt 1)
ws reconnecting in 2s (attempt 2)
ws reconnecting in 4s (attempt 3)
...
```

---

### Тест 3.5 — Прокрутка к оригиналу при тапе на reply

**Цель:** Тап на цитату в сообщении скроллит к оригиналу.

1. Откройте чат с сообщениями и ответами (reply)
2. Найдите сообщение, которое является ответом на другое (видна цветная полоска с цитатой)
3. **Нажмите на цитату** (на серый блок с именем и текстом оригинала)
4. **Ожидаемый результат:** Список плавно прокручивается к оригинальному сообщению

**Граничный случай:** Если оригинальное сообщение не в текущей загруженной порции — прокрутки не будет (сообщение не найдено в `_messages`). В этом случае нужно сначала прокрутить вверх чтобы подгрузить историю.

---

### Тест 3.8 — "Был(а) N мин назад"

**Цель:** В шапке DM-чата показывается время последней активности партнёра.

1. Откройте любой DM-чат (не групповой)
2. Подождите несколько секунд пока загрузится профиль партнёра
3. **Ожидаемый результат:** Под именем партнёра в шапке:
   - Если партнёр в сети → "В сети" (зелёный)
   - Если не в сети → "был(а) N мин назад" / "был(а) N ч назад" и т.д. (серый)
4. Отключите партнёра (выйдите из его сессии) — через несколько минут текст обновится

**Примечание:** Текст "был(а) N мин назад" не обновляется real-time (только при открытии чата). Для обновления на лету потребовался бы отдельный timer — это не реализовано.

---

### Тест 4.2 — Multi-select сообщений

**Цель:** Long press входит в режим выбора, можно удалить несколько сообщений.

**Войти в режим выбора:**
1. Длительно нажмите (long press) на любое сообщение
2. **Ожидаемый результат:** Сообщение подсвечивается фиолетовым, шапка чата меняется: появляется "Выбрано: 1" + кнопки "Переслать" и "Удалить"

**Добавить/убрать сообщения:**
3. Коротко нажмите на другие сообщения — они добавляются в выборку (подсвечиваются)
4. Нажмите на уже выбранное — снимается выбор

**Удалить:**
5. Нажмите кнопку "Удалить" (корзина, красная)
6. Появится диалог "Удалить N сообщ.?"
7. Подтвердите → сообщения пропадают у всех участников

**Переслать:**
8. Нажмите кнопку "Переслать" (стрелка)
9. Откроется sheet с выбором чата — выберите получателя
10. Первое выбранное сообщение будет переслано

**Выход из режима:**
11. Нажмите "X" в шапке или сделайте так, чтобы Set стал пустым

---

### Тест forward UI (4.1, уже было)

**Цель:** Убедиться, что пересылка работает.

1. Long press на любое сообщение → контекстное меню
2. Выберите "Переслать"
3. Откроется bottom sheet со списком ваших чатов
4. Выберите получателя
5. **Ожидаемый результат:** В чате получателя появится сообщение с плашкой "Переслано от @username"

---

## Известные ограничения

1. **Reply scroll приблизительный** — offset рассчитывается как `index * 80px`. При разнородных по высоте сообщениях может промахнуться. Точный скролл требует GlobalKey на каждый элемент.

2. **"Был(а) N мин назад" не обновляется real-time** — загружается однократно при открытии чата. При желании можно добавить periodic timer.

3. **Multi-select пересылает только первое** сообщение из набора — пересылка нескольких одновременно требует изменений в API и UI.

4. **Rate limiting in-memory** — при рестарте бэкенда счётчики сбрасываются. Для продакшна нужен Redis-бэкенд (Phase 2 в roadmap).

5. **WS CORS** — Flutter desktop/mobile клиенты не отправляют Origin, поэтому для них CORS проверка не работает (всегда пропускается). Это корректное поведение нативных WS-клиентов.

6. **Link preview (4.3)** — не реализован. Требует либо backend proxy для og-тегов, либо прямой fetch с CORS-разрешения.
