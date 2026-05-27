ALTER TABLE messages
    DROP COLUMN IF EXISTS file_name,
    DROP COLUMN IF EXISTS file_size;
