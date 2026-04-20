DROP TABLE IF EXISTS users CASCADE;

DROP INDEX IF NOT EXISTS idx_users_username ON users(username);
DROP INDEX IF NOT EXISTS idx_users_last_name ON users(last_name);