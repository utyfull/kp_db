BEGIN;
SET search_path = clown_gpt, public;

-- Универсальный аудит
CREATE OR REPLACE FUNCTION audit_log_change() RETURNS trigger AS $$
DECLARE
  v_user uuid := null;
BEGIN
  BEGIN
    v_user := current_setting('clown_gpt.current_user_id', true)::uuid;
  EXCEPTION WHEN others THEN
    v_user := NULL;
  END;

  INSERT INTO audit_log(table_name, operation, record_pk, old_data, new_data, changed_by, client_addr, application_name)
  VALUES (
    TG_TABLE_NAME,
    TG_OP,
    CASE WHEN TG_OP = 'INSERT' THEN to_jsonb(NEW.*) ELSE to_jsonb(OLD.*) END,
    CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD.*) END,
    CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW.*) END,
    v_user,
    inet_client_addr(),
    current_setting('application_name', true)
  );
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Статистика чатов/проектов
CREATE OR REPLACE FUNCTION chat_stats_ensure(p_chat_id uuid) RETURNS void AS $$
BEGIN
  INSERT INTO chat_stats(chat_id) VALUES (p_chat_id)
  ON CONFLICT (chat_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION project_stats_ensure(p_project_id uuid) RETURNS void AS $$
BEGIN
  INSERT INTO project_stats(project_id) VALUES (p_project_id)
  ON CONFLICT (project_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_chat_stats_init() RETURNS trigger AS $$
BEGIN
  PERFORM chat_stats_ensure(NEW.id);
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_messages_aggregate() RETURNS trigger AS $$
DECLARE
  v_chat_id uuid;
  v_project_id uuid;
  v_sign int := 1;
  v_sender message_sender_type;
  v_created timestamptz;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_chat_id := OLD.chat_id;
    v_sign := -1;
    v_sender := OLD.sender_type;
    v_created := OLD.created_at;
  ELSE
    v_chat_id := NEW.chat_id;
    v_sender := NEW.sender_type;
    v_created := NEW.created_at;
  END IF;

  SELECT project_id INTO v_project_id FROM chats WHERE id = v_chat_id;

  PERFORM chat_stats_ensure(v_chat_id);

  UPDATE chat_stats
  SET message_count = message_count + v_sign,
      user_message_count = user_message_count + CASE WHEN v_sender = 'user' THEN v_sign ELSE 0 END,
      assistant_message_count = assistant_message_count + CASE WHEN v_sender = 'assistant' THEN v_sign ELSE 0 END,
      system_message_count = system_message_count + CASE WHEN v_sender = 'system' THEN v_sign ELSE 0 END,
      last_message_at = CASE WHEN v_sign > 0 AND (last_message_at IS NULL OR v_created > last_message_at) THEN v_created ELSE last_message_at END,
      updated_at = now()
  WHERE chat_id = v_chat_id;

  SELECT project_id INTO v_project_id FROM chats WHERE id = v_chat_id;
  IF v_project_id IS NOT NULL THEN
    PERFORM project_stats_ensure(v_project_id);
    UPDATE project_stats
    SET message_count = message_count + v_sign,
        last_activity_at = CASE WHEN v_sign > 0 AND (last_activity_at IS NULL OR v_created > last_activity_at) THEN v_created ELSE last_activity_at END,
        updated_at = now()
    WHERE project_id = v_project_id;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_messages_recount() RETURNS trigger AS $$
DECLARE
  v_chat_id uuid;
  v_project_id uuid;
BEGIN
  v_chat_id := COALESCE(NEW.chat_id, OLD.chat_id);
  SELECT project_id INTO v_project_id FROM chats WHERE id = v_chat_id;

  PERFORM chat_stats_ensure(v_chat_id);
  UPDATE chat_stats cs
  SET message_count = s.message_count,
      user_message_count = s.user_message_count,
      assistant_message_count = s.assistant_message_count,
      system_message_count = s.system_message_count,
      last_message_at = s.last_message_at,
      updated_at = now()
  FROM (
    SELECT
      COUNT(*) FILTER (WHERE deleted_at IS NULL) AS message_count,
      COUNT(*) FILTER (WHERE sender_type = 'user' AND deleted_at IS NULL) AS user_message_count,
      COUNT(*) FILTER (WHERE sender_type = 'assistant' AND deleted_at IS NULL) AS assistant_message_count,
      COUNT(*) FILTER (WHERE sender_type = 'system' AND deleted_at IS NULL) AS system_message_count,
      MAX(created_at) FILTER (WHERE deleted_at IS NULL) AS last_message_at
    FROM messages WHERE chat_id = v_chat_id
  ) s
  WHERE cs.chat_id = v_chat_id;

  IF v_project_id IS NOT NULL THEN
    PERFORM project_stats_ensure(v_project_id);
    UPDATE project_stats ps
    SET message_count = s.message_count,
        last_activity_at = s.last_message_at,
        updated_at = now()
    FROM (
      SELECT
        COUNT(*) FILTER (WHERE m.deleted_at IS NULL) AS message_count,
        MAX(m.created_at) FILTER (WHERE m.deleted_at IS NULL) AS last_message_at
      FROM messages m
      JOIN chats c ON c.id = m.chat_id
      WHERE c.project_id = v_project_id
    ) s
    WHERE ps.project_id = v_project_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_chats_aggregate() RETURNS trigger AS $$
DECLARE
  v_project uuid;
  v_sign int := 1;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_project := OLD.project_id;
    v_sign := -1;
  ELSE
    v_project := NEW.project_id;
  END IF;

  IF v_project IS NOT NULL THEN
    PERFORM project_stats_ensure(v_project);
    UPDATE project_stats
    SET chat_count = chat_count + v_sign,
        last_activity_at = CASE WHEN v_sign > 0 THEN COALESCE(last_activity_at, now()) ELSE last_activity_at END,
        updated_at = now()
    WHERE project_id = v_project;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Скалярные функции
CREATE OR REPLACE FUNCTION fn_chat_message_count(p_chat_id uuid) RETURNS integer AS $$
  SELECT COALESCE(message_count, 0) FROM chat_stats WHERE chat_id = p_chat_id;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_user_message_count(p_user_id uuid) RETURNS integer AS $$
  SELECT COALESCE(SUM(cs.user_message_count), 0)
  FROM chats c
  JOIN chat_stats cs ON cs.chat_id = c.id
  WHERE c.owner_user_id = p_user_id;
$$ LANGUAGE sql STABLE;

-- Табличные функции
CREATE OR REPLACE FUNCTION fn_project_report(p_org uuid DEFAULT NULL) RETURNS TABLE (
  project_id uuid,
  project_name text,
  chat_count integer,
  message_count integer,
  last_activity timestamptz
) AS $$
  SELECT p.id, p.name, COALESCE(ps.chat_count, 0), COALESCE(ps.message_count, 0), ps.last_activity_at
  FROM projects p
  LEFT JOIN project_stats ps ON ps.project_id = p.id
  WHERE (p.organization_id = p_org OR p_org IS NULL);
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_model_usage_report(p_org uuid DEFAULT NULL) RETURNS TABLE (
  model_id integer,
  model_name text,
  total_tokens_in bigint,
  total_tokens_out bigint,
  calls bigint
) AS $$
  SELECT ue.model_id,
         m.name,
         SUM(ue.tokens_in)::bigint,
         SUM(ue.tokens_out)::bigint,
         COUNT(*)::bigint AS calls
  FROM usage_events ue
  LEFT JOIN models m ON m.id = ue.model_id
  WHERE (ue.organization_id = p_org OR p_org IS NULL)
  GROUP BY ue.model_id, m.name
  ORDER BY calls DESC NULLS LAST;
$$ LANGUAGE sql STABLE;

-- Триггеры аудита
CREATE TRIGGER trg_audit_users    AFTER INSERT OR UPDATE OR DELETE ON users    FOR EACH ROW EXECUTE FUNCTION audit_log_change();
CREATE TRIGGER trg_audit_projects AFTER INSERT OR UPDATE OR DELETE ON projects FOR EACH ROW EXECUTE FUNCTION audit_log_change();
CREATE TRIGGER trg_audit_chats    AFTER INSERT OR UPDATE OR DELETE ON chats    FOR EACH ROW EXECUTE FUNCTION audit_log_change();
CREATE TRIGGER trg_audit_messages AFTER INSERT OR UPDATE OR DELETE ON messages FOR EACH ROW EXECUTE FUNCTION audit_log_change();
CREATE TRIGGER trg_audit_usage    AFTER INSERT OR UPDATE OR DELETE ON usage_events FOR EACH ROW EXECUTE FUNCTION audit_log_change();

-- Триггеры агрегаций
CREATE TRIGGER trg_chats_project_stats
AFTER INSERT OR DELETE ON chats
FOR EACH ROW EXECUTE FUNCTION trg_chats_aggregate();

CREATE TRIGGER trg_messages_stats
AFTER INSERT OR DELETE ON messages
FOR EACH ROW EXECUTE FUNCTION trg_messages_aggregate();

CREATE TRIGGER trg_messages_recount
AFTER UPDATE OF sender_type, deleted_at ON messages
FOR EACH ROW EXECUTE FUNCTION trg_messages_recount();

CREATE TRIGGER trg_chat_stats_init
AFTER INSERT ON chats
FOR EACH ROW EXECUTE FUNCTION trg_chat_stats_init();

COMMIT;
