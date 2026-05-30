CREATE INDEX IF NOT EXISTS idx_messages_content ON messages USING gin(to_tsvector('simple', content))
    WHERE deleted_at IS NULL;
