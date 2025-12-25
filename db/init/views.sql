BEGIN;
SET search_path = clown_gpt, public;

CREATE OR REPLACE VIEW view_user_activity AS
SELECT
  u.id AS user_id,
  u.username,
  u.role,
  COUNT(DISTINCT c.id) AS owned_chats,
  COALESCE(SUM(cs.user_message_count), 0) AS user_messages,
  COALESCE(SUM(cs.assistant_message_count), 0) AS assistant_messages
FROM users u
LEFT JOIN chats c ON c.owner_user_id = u.id
LEFT JOIN chat_stats cs ON cs.chat_id = c.id
GROUP BY u.id, u.username, u.role;

CREATE OR REPLACE VIEW view_project_summary AS
SELECT
  p.id AS project_id,
  p.name,
  p.visibility,
  COALESCE(ps.chat_count, 0) AS chat_count,
  COALESCE(ps.message_count, 0) AS message_count,
  ps.last_activity_at
FROM projects p
LEFT JOIN project_stats ps ON ps.project_id = p.id
WHERE p.deleted_at IS NULL;

CREATE OR REPLACE VIEW view_daily_model_usage AS
SELECT
  date_trunc('day', ue.happened_at) AS day,
  m.name AS model_name,
  COUNT(*) AS calls,
  SUM(ue.tokens_in) AS tokens_in,
  SUM(ue.tokens_out) AS tokens_out,
  SUM(ue.cost) AS cost
FROM usage_events ue
LEFT JOIN models m ON m.id = ue.model_id
GROUP BY date_trunc('day', ue.happened_at), m.name
ORDER BY day DESC, model_name;

COMMIT;
