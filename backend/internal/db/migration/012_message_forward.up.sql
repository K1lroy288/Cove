ALTER TABLE messages
    ADD COLUMN forwarded_from_id       BIGINT,
    ADD COLUMN forwarded_from_username TEXT;
