BEGIN;
SET search_path = clown_gpt, public;

-- B-Tree индексы 
CREATE INDEX IF NOT EXISTS idx_users_username ON users (username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_projects_owner ON projects (owner_user_id);
CREATE INDEX IF NOT EXISTS idx_projects_updated_at ON projects (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_chats_owner ON chats (owner_user_id);
CREATE INDEX IF NOT EXISTS idx_chats_project ON chats (project_id);
CREATE INDEX IF NOT EXISTS idx_chats_updated_at ON chats (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_chat ON messages (chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_events_org ON usage_events (organization_id);
CREATE INDEX IF NOT EXISTS idx_usage_events_model ON usage_events (model_id);
CREATE INDEX IF NOT EXISTS idx_usage_events_happened_at ON usage_events (happened_at DESC);

-- GIN индексы для JSONB полей
CREATE INDEX IF NOT EXISTS idx_users_settings_gin ON users USING gin (settings);
CREATE INDEX IF NOT EXISTS idx_messages_meta_gin ON messages USING gin (meta);
CREATE INDEX IF NOT EXISTS idx_usage_events_meta_gin ON usage_events USING gin (meta);

-- BRIN индексы 
CREATE INDEX IF NOT EXISTS idx_messages_created_at_brin ON messages USING brin (created_at);
CREATE INDEX IF NOT EXISTS idx_usage_events_happened_at_brin ON usage_events USING brin (happened_at);

COMMIT;
