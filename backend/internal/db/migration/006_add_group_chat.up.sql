ALTER TABLE chats
    ADD COLUMN chat_type  VARCHAR(10) NOT NULL DEFAULT 'dm'
                          CHECK (chat_type IN ('dm', 'group')),
    ADD COLUMN name       VARCHAR(100),
    ADD COLUMN avatar     VARCHAR(10),
    ADD COLUMN created_by INTEGER REFERENCES users(id);

ALTER TABLE chats
    ADD CONSTRAINT chk_group_name
    CHECK (chat_type = 'dm' OR name IS NOT NULL);

ALTER TABLE chat_members
    ADD COLUMN role VARCHAR(10) NOT NULL DEFAULT 'member'
                    CHECK (role IN ('member', 'admin'));

CREATE INDEX idx_chat_members_chat_role ON chat_members(chat_id, role);
