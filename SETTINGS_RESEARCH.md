# Research: Система настроек в Cove

## Что уже есть в коде

- `users.settings JSONB` — уже есть в миграции 001 и в `model.User.Settings datatypes.JSON`
- Stub-страница настроек в `main_screen.dart` — меню без логики (Logout работает, остальное — заглушки)
- **Нет:** никаких эндпоинтов, DTO, service/repo методов, Flutter-кода для настроек

---

## Где хранить: Server vs Client

| Категория | Где | Почему |
|---|---|---|
| Тема (dark/light) | **Сервер** | Discord и Slack синхронизируют между устройствами |
| Глобальные уведомления | **Сервер** | Должны работать на всех устройствах |
| Mute конкретного чата | **Сервер** — отдельная таблица | Запрашивается на каждом входящем сообщении, нужен fast indexed lookup по `(user_id, chat_id)` |
| DND расписание (тихие часы) | **Сервер** | Cross-device |
| Read receipts / typing indicators | **Сервер** | Влияет на поведение протокола, видно собеседнику |
| Онлайн-статус (видимость) | **Сервер** | Влияет на других пользователей |
| Язык интерфейса | **Сервер** | Новое устройство должно сразу показать правильный язык |
| Голос: VAD vs PTT, шумоподавление | **Сервер** | Preference, не железо — нужна синхронизация |
| Голос: конкретный микрофон/колонки | **Клиент** | UUID железа бессмысленен на другом устройстве |
| PTT-кнопка (hotkey) | **Клиент** | Привязана к клавиатуре конкретной машины |
| Автозагрузка медиа | **Клиент** | Зависит от хранилища и тарифа конкретного девайса |

**Правило:** влияет на других или должно работать на всех устройствах → сервер. Привязано к железу или хранилищу → клиент.

---

## JSONB vs отдельные колонки vs ключ-значение

| Подход | Плюсы | Минусы | Вывод |
|---|---|---|---|
| **JSONB-блоб** | Нет миграций при новых ключах, один SELECT, GIN-индекс | Нет FK/constraints, плохо для фильтрации/аналитики | Основное хранилище для большинства preferences |
| **Отдельные колонки** | Тип-безопасность, индексы, статистика | Каждая настройка = миграция | Только `theme` и `locale` |
| **Таблица ключ-значение** | Бесконечно расширяема | N запросов чтобы прочитать всё, нет типов | Нет |
| **Отдельная таблица per-chat** | Составной индекс `(user_id, chat_id)`, fast lookup | Ещё одна таблица | Только для per-chat mute, т.к. нужен indexed lookup |

**Вывод для Cove:** `user_settings` с колонками `theme`, `locale` + `preferences JSONB` для всего остального. Плюс отдельная `chat_notification_settings`.

---

## Что реализовывать: Phase 1 (MVP)

### Глобальные настройки — `preferences JSONB`

**Уведомления**
```json
"notifications_enabled": true,       // полностью выключить все уведомления
"notification_sound": "default",      // имя звука
"notification_preview": true,         // показывать текст сообщения в пуше
"dnd_enabled": false,                 // режим «не беспокоить»
"dnd_start": "23:00",                 // начало тихих часов (HH:MM)
"dnd_end": "08:00"                    // конец тихих часов (HH:MM)
```

**Приватность**
```json
"read_receipts_enabled": true,        // галочки прочтения
"typing_indicators_enabled": true,    // «печатает...»
"online_status_visible": true         // показывать онлайн другим пользователям
```

### Отдельные колонки в `user_settings`
```
theme:  VARCHAR(10)  DEFAULT 'dark'   -- 'dark' | 'light' | 'auto'
locale: VARCHAR(10)  DEFAULT 'ru'     -- 'ru' | 'en' | ...
```

### Per-chat — `chat_notification_settings`
```
muted:        BOOLEAN       DEFAULT FALSE
mute_until:   TIMESTAMPTZ   NULL = навсегда заглушен
notify_level: SMALLINT      0=inherit | 1=all | 2=nothing
```

---

## Что реализовывать: Phase 2 (после голосовых комнат)

### Голос — добавить в `preferences JSONB`
```json
"voice_input_mode": "vad",            // "vad" (Voice Activity Detection) | "ptt" (Push-to-Talk)
"voice_noise_suppression": "medium",  // "disabled" | "low" | "medium" | "high"
"voice_echo_cancellation": true,
"voice_auto_gain": true,
"voice_vad_threshold": -40.0          // порог в dB для VAD
```

### Чат — добавить в `preferences JSONB`
```json
"compact_mode": false,                // компактное отображение сообщений
"font_scale": 1.0,                    // масштаб шрифта (0.8–1.5)
"link_previews_enabled": true,        // превью ссылок
"enter_sends_message": true           // Enter = отправить (vs Shift+Enter)
```

---

## Схема БД

```sql
-- Новая таблица (миграция 005)
CREATE TABLE user_settings (
  user_id     BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  theme       VARCHAR(10)  NOT NULL DEFAULT 'dark',
  locale      VARCHAR(10)  NOT NULL DEFAULT 'ru',
  preferences JSONB        NOT NULL DEFAULT '{}',
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Per-chat mute (миграция 005)
CREATE TABLE chat_notification_settings (
  user_id      BIGINT   NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chat_id      BIGINT   NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  muted        BOOLEAN  NOT NULL DEFAULT FALSE,
  mute_until   TIMESTAMPTZ,
  notify_level SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, chat_id)
);
CREATE INDEX idx_cns_user ON chat_notification_settings(user_id);
```

> Существующая `users.settings JSONB` колонка остаётся, но новые настройки пишутся в `user_settings`. Можно убрать `users.settings` в отдельной миграции позже.

---

## Backend: новые файлы и эндпоинты

```
internal/model/user_settings.go          — UserSettings, ChatNotificationSettings GORM-модели
internal/DTO/settings.go                 — UserSettingsDTO, UpdateSettingsRequest, ChatNotifSettingsDTO
internal/repository/settings_repository.go
  - GetUserSettings(userID) → upsert дефолта если строки нет
  - UpdateUserSettings(userID, patch) → для preferences: "preferences = preferences || $1::jsonb"
  - GetChatNotifSettings(userID, chatID)
  - UpsertChatNotifSettings(s)
internal/service/settings_service.go
internal/handler/settings_handler.go
```

**Эндпоинты (добавить в main.go под JWTAuth):**
```
GET  /settings              → UserSettingsDTO (создаёт дефолт при первом запросе)
PATCH /settings             → partial update: theme, locale, любые preferences-ключи
GET  /settings/chat/:id     → ChatNotifSettingsDTO
PATCH /settings/chat/:id    → { muted, mute_until, notify_level }
```

---

## Frontend: новая фича

```
features/settings/
├── data/
│   ├── models/user_settings.dart        — UserSettings.fromJson, copyWith
│   └── services/settings_service.dart   — GET/PATCH
└── presentation/
    ├── settings_notifier.dart            — ChangeNotifier: loadSettings, updateTheme, ...
    └── settings_screen.dart             — заменяет stub
```

**`lib/main.dart`:**
- `SettingsNotifier` добавить в `MultiProvider`
- `Consumer<SettingsNotifier>` вокруг `MaterialApp` → `theme: settings.theme == 'light' ? lightTheme : darkTheme`
- При логине: `settingsNotifier.loadSettings(token)`
- При логауте: `settingsNotifier.clear()`

**UI настроек:**
- «Внешний вид» → переключатель dark/light (мгновенное применение)
- «Уведомления» → `notifications_enabled`, `notification_preview`, DND расписание
- «Приватность» → `read_receipts_enabled`, `typing_indicators_enabled`, `online_status_visible`
- «Аккаунт» → логаут (уже работает)
- Per-chat mute → иконка 🔔 в header чата → bottom sheet с выбором длительности

---

## Уроки из конкурентов

- **Discord** хранит всё server-side, протобуф. Иерархия уведомлений: global → per-server → per-channel. Для Cove: global + per-chat достаточно на Phase 1.
- **Telegram** — гибрид: приватность и mute server-side, звуки уведомлений client-local. Mute — самая используемая функция.
- **Signal** — всё client-only по соображениям приватности. Не подходит для нас.
- **Slack** — всё server-side. `enter_is_special_key` (Enter = send) — постоянный запрос от десктоп-пользователей.
- **Mumble** — детальные аудио-настройки: VAD threshold, jitter buffer, bitrate. Эталон для Phase 2 голоса.

**Top-5 настроек по частоте использования (по данным всех приложений):**
1. Per-chat mute — самая востребованная
2. Dark mode
3. `notifications_enabled` (глобальное отключение)
4. DND расписание (тихие часы)
5. `read_receipts_enabled`
