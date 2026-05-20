DROP INDEX IF EXISTS idx_chat_members_chat_role;

ALTER TABLE chat_members DROP COLUMN IF EXISTS role;

ALTER TABLE chats DROP CONSTRAINT IF EXISTS chk_group_name;

ALTER TABLE chats
    DROP COLUMN IF EXISTS created_by,
    DROP COLUMN IF EXISTS avatar,
    DROP COLUMN IF EXISTS name,
    DROP COLUMN IF EXISTS chat_type;
