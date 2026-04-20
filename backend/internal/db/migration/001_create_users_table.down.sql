DROP TABLE IF EXISTS users CASCADE;

DROP INDEX IF NOT EXISTS idx_users_username ON users(username);