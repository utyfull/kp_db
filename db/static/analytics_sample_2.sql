SET search_path TO clown_gpt, public;
EXPLAIN ANALYZE
SELECT
  u.username,
  COUNT(*) FILTER (WHERE m.sender_type = 'user') AS user_messages,
  COUNT(*) FILTER (WHERE m.sender_type = 'assistant') AS assistant_messages,
  MAX(m.created_at) AS last_msg_at
FROM messages m
JOIN chats c ON c.id = m.chat_id
JOIN users u ON u.id = c.owner_user_id
WHERE m.created_at >= now() - interval '30 days'
GROUP BY u.username
ORDER BY user_messages DESC, last_msg_at DESC;
