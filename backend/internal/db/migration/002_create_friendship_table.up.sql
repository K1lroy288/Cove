CREATE TYPE friendship_status AS ENUM ('pending', 'accepted', 'blocked');

CREATE TABLE IF NOT EXISTS friendships (
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status friendship_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    -- Чтобы нельзя было добавить одного и того же друга дважды
    PRIMARY KEY (user_id, friend_id),
    -- Чтобы нельзя было дружить с самим собой на уровне БД
    CONSTRAINT check_not_self CHECK (user_id <> friend_id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_status ON friendships(status);