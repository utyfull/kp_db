SET search_path TO clown_gpt, public;
EXPLAIN ANALYZE
SELECT
  m.name AS model_name,
  COUNT(*) AS calls,
  SUM(ue.tokens_in) AS tokens_in,
  SUM(ue.tokens_out) AS tokens_out,
  SUM(ue.cost) AS cost
FROM usage_events ue
LEFT JOIN models m ON m.id = ue.model_id
WHERE ue.happened_at >= now() - interval '7 days'
GROUP BY m.name
ORDER BY cost DESC NULLS LAST;
