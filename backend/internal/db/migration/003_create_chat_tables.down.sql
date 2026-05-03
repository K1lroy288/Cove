DROP TABLE IF EXISTS chat_read_cursors;
DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS chat_members;
ALTER TABLE chats DROP CONSTRAINT IF EXISTS fk_chats_last_message;
DROP TABLE IF EXISTS chats;
