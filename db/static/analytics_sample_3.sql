SET search_path TO clown_gpt, public;
EXPLAIN ANALYZE
SELECT
  p.id,
  p.name,
  COALESCE(ps.chat_count, 0) AS chat_count,
  COALESCE(ps.message_count, 0) AS message_count,
  ps.last_activity_at
FROM projects p
LEFT JOIN project_stats ps ON ps.project_id = p.id
ORDER BY ps.message_count DESC NULLS LAST, ps.last_activity_at DESC NULLS LAST;
