ALTER TABLE messages
    ADD COLUMN file_name VARCHAR(255),
    ADD COLUMN file_size BIGINT;
