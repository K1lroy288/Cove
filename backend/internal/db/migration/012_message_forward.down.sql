ALTER TABLE messages
    DROP COLUMN IF EXISTS forwarded_from_id,
    DROP COLUMN IF EXISTS forwarded_from_username;
