CREATE TABLE IF NOT EXISTS user_settings (
    user_id     BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    theme       VARCHAR(10)  NOT NULL DEFAULT 'dark',
    locale      VARCHAR(10)  NOT NULL DEFAULT 'ru',
    preferences JSONB        NOT NULL DEFAULT '{}',
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chat_notification_settings (
    user_id      BIGINT   NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    chat_id      BIGINT   NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    muted        BOOLEAN  NOT NULL DEFAULT FALSE,
    mute_until   TIMESTAMPTZ,
    notify_level SMALLINT NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, chat_id)
);

CREATE INDEX IF NOT EXISTS idx_cns_user ON chat_notification_settings(user_id);
