ALTER TABLE chat_read_cursors
  ADD COLUMN last_delivered_message_id INTEGER REFERENCES messages(id);
