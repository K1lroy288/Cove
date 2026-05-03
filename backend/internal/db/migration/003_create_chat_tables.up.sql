CREATE TABLE IF NOT EXISTS chats (
    id                    SERIAL PRIMARY KEY,
    last_message_id       INTEGER,
    last_message_at       TIMESTAMPTZ,
    last_message_content  TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chat_members (
    chat_id   INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id          SERIAL PRIMARY KEY,
    chat_id     INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    sender_id   INTEGER NOT NULL REFERENCES users(id),
    content     TEXT    NOT NULL,
    type        VARCHAR(20) NOT NULL DEFAULT 'text',
    reply_to_id INTEGER REFERENCES messages(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    edited_at   TIMESTAMPTZ,
    deleted_at  TIMESTAMPTZ
);

-- FK добавляем после создания messages, т.к. chats ссылается на messages
ALTER TABLE chats
    ADD CONSTRAINT fk_chats_last_message
    FOREIGN KEY (last_message_id) REFERENCES messages(id);

CREATE TABLE IF NOT EXISTS chat_read_cursors (
    chat_id              INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    user_id              INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_message_id INTEGER REFERENCES messages(id),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (chat_id, user_id)
);

-- Индекс для cursor-based пагинации: WHERE chat_id=? [AND id < ?] ORDER BY id DESC
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id, id DESC);

-- Индекс для поиска чатов пользователя: WHERE user_id=?
CREATE INDEX IF NOT EXISTS idx_chat_members_user_id ON chat_members(user_id);
