BEGIN;

CREATE SCHEMA clown_gpt;
SET search_path = clown_gpt, public;

CREATE EXTENSION pgcrypto;
CREATE EXTENSION citext;

CREATE TYPE user_role AS ENUM ('admin','member','moderator');
CREATE TYPE membership_role AS ENUM ('owner','editor','viewer');
CREATE TYPE project_visibility AS ENUM ('private','shared','public');
CREATE TYPE chat_status AS ENUM ('active','archived','deleted');
CREATE TYPE message_sender_type AS ENUM ('user','assistant','system','tool');
CREATE TYPE usage_event_type AS ENUM ('chat_completion','embedding','other');
CREATE TYPE invoice_status AS ENUM ('draft','issued','paid','void');

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  username citext NOT NULL UNIQUE,
  email citext NOT NULL UNIQUE,
  password_hash text NOT NULL,
  role user_role NOT NULL DEFAULT 'member',
  is_active boolean NOT NULL DEFAULT true,
  email_verified boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_login_at timestamptz,
  last_ip inet,
  settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  deleted_at timestamptz,
  CONSTRAINT users_username_len_chk CHECK (char_length(username::text) BETWEEN 3 AND 32),
  CONSTRAINT users_email_has_at_chk CHECK (position('@' IN email::text) > 1),
  CONSTRAINT users_not_deleted_active_chk CHECK ((deleted_at IS NULL) OR (is_active = false))
);

CREATE TABLE user_profiles (
  user_id uuid PRIMARY KEY,
  display_name text NOT NULL,
  bio text NOT NULL DEFAULT '',
  avatar_url text,
  locale text NOT NULL DEFAULT 'ru-RU',
  timezone text NOT NULL DEFAULT 'Europe/Moscow',
  preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT user_profiles_display_name_len_chk CHECK (char_length(display_name) BETWEEN 1 AND 80)
);

CREATE TABLE auth_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  session_token text NOT NULL UNIQUE,
  user_agent text NOT NULL DEFAULT '',
  client_ip inet,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT auth_sessions_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT auth_sessions_exp_chk CHECK (expires_at > created_at)
);

CREATE TABLE password_reset_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  token_hash text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  request_ip inet,
  request_ua text NOT NULL DEFAULT '',
  CONSTRAINT prt_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT prt_exp_chk CHECK (expires_at > created_at),
  CONSTRAINT prt_used_chk CHECK (used_at IS NULL OR used_at >= created_at)
);

CREATE TABLE api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  name text NOT NULL,
  key_prefix text NOT NULL,
  key_hash text NOT NULL UNIQUE,
  scopes text[] NOT NULL DEFAULT ARRAY['chat:read','chat:write']::text[],
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  last_ip inet,
  CONSTRAINT api_keys_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT api_keys_name_len_chk CHECK (char_length(name) BETWEEN 1 AND 80),
  CONSTRAINT api_keys_prefix_len_chk CHECK (char_length(key_prefix) BETWEEN 6 AND 16)
);

CREATE TABLE organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug citext NOT NULL UNIQUE,
  name text NOT NULL,
  owner_user_id uuid NOT NULL,
  billing_email citext NOT NULL,
  plan text NOT NULL DEFAULT 'free',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT orgs_owner_fk FOREIGN KEY (owner_user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT orgs_slug_len_chk CHECK (char_length(slug::text) BETWEEN 3 AND 40),
  CONSTRAINT orgs_name_len_chk CHECK (char_length(name) BETWEEN 1 AND 120),
  CONSTRAINT orgs_billing_email_chk CHECK (position('@' IN billing_email::text) > 1)
);

CREATE TABLE organization_members (
  organization_id uuid NOT NULL,
  user_id uuid NOT NULL,
  member_role membership_role NOT NULL DEFAULT 'viewer',
  can_billing boolean NOT NULL DEFAULT false,
  joined_at timestamptz NOT NULL DEFAULT now(),
  invited_by uuid,
  is_active boolean NOT NULL DEFAULT true,
  PRIMARY KEY (organization_id, user_id),
  CONSTRAINT org_mem_org_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT org_mem_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT org_mem_invited_by_fk FOREIGN KEY (invited_by) REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE models (
  id smallserial PRIMARY KEY,
  name text NOT NULL UNIQUE,
  provider text NOT NULL DEFAULT 'clown',
  version text NOT NULL,
  context_window integer NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  price_input_1k numeric(10,4) NOT NULL DEFAULT 0,
  price_output_1k numeric(10,4) NOT NULL DEFAULT 0,
  capabilities jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT models_name_len_chk CHECK (char_length(name) BETWEEN 3 AND 64),
  CONSTRAINT models_ctx_chk CHECK (context_window >= 256),
  CONSTRAINT models_price_chk CHECK (price_input_1k >= 0 AND price_output_1k >= 0)
);

CREATE TABLE projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid,
  owner_user_id uuid NOT NULL,
  name text NOT NULL,
  description text NOT NULL DEFAULT '',
  visibility project_visibility NOT NULL DEFAULT 'private',
  archived boolean NOT NULL DEFAULT false,
  settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT projects_org_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT projects_owner_fk FOREIGN KEY (owner_user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT projects_name_len_chk CHECK (char_length(name) BETWEEN 1 AND 120)
);

CREATE TABLE project_members (
  project_id uuid NOT NULL,
  user_id uuid NOT NULL,
  member_role membership_role NOT NULL DEFAULT 'viewer',
  can_invite boolean NOT NULL DEFAULT false,
  is_favorite boolean NOT NULL DEFAULT false,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (project_id, user_id),
  CONSTRAINT proj_mem_project_fk FOREIGN KEY (project_id) REFERENCES projects(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT proj_mem_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE chats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid,
  organization_id uuid,
  owner_user_id uuid NOT NULL,
  title text NOT NULL,
  status chat_status NOT NULL DEFAULT 'active',
  pinned boolean NOT NULL DEFAULT false,
  model_id integer NOT NULL,
  temperature numeric(3,2) NOT NULL DEFAULT 0.70,
  max_output_tokens integer NOT NULL DEFAULT 1024,
  system_prompt text NOT NULL DEFAULT '',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT chats_project_fk FOREIGN KEY (project_id) REFERENCES projects(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT chats_org_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT chats_owner_fk FOREIGN KEY (owner_user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT chats_model_fk FOREIGN KEY (model_id) REFERENCES models(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT chats_title_len_chk CHECK (char_length(title) BETWEEN 1 AND 200),
  CONSTRAINT chats_temp_chk CHECK (temperature >= 0 AND temperature <= 2),
  CONSTRAINT chats_max_tokens_chk CHECK (max_output_tokens >= 1 AND max_output_tokens <= 32768)
);

CREATE TABLE chat_members (
  chat_id uuid NOT NULL,
  user_id uuid NOT NULL,
  member_role membership_role NOT NULL DEFAULT 'viewer',
  muted boolean NOT NULL DEFAULT false,
  last_read_at timestamptz,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (chat_id, user_id),
  CONSTRAINT chat_mem_chat_fk FOREIGN KEY (chat_id) REFERENCES chats(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT chat_mem_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE messages (
  id bigserial PRIMARY KEY,
  chat_id uuid NOT NULL,
  sender_user_id uuid,
  sender_type message_sender_type NOT NULL,
  content text NOT NULL,
  token_input integer NOT NULL DEFAULT 0,
  token_output integer NOT NULL DEFAULT 0,
  cost_estimated numeric(12,6) NOT NULL DEFAULT 0,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  CONSTRAINT messages_chat_fk FOREIGN KEY (chat_id) REFERENCES chats(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT messages_sender_fk FOREIGN KEY (sender_user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT messages_content_len_chk CHECK (char_length(content) BETWEEN 1 AND 8000),
  CONSTRAINT messages_tokens_chk CHECK (token_input >= 0 AND token_output >= 0),
  CONSTRAINT messages_cost_chk CHECK (cost_estimated >= 0)
);

CREATE TABLE tags (
  id bigserial PRIMARY KEY,
  organization_id uuid,
  name citext NOT NULL,
  color text NOT NULL DEFAULT 'gray',
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tags_org_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT tags_created_by_fk FOREIGN KEY (created_by) REFERENCES users(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT tags_name_len_chk CHECK (char_length(name::text) BETWEEN 1 AND 40),
  CONSTRAINT tags_color_len_chk CHECK (char_length(color) BETWEEN 1 AND 20),
  CONSTRAINT tags_unique_per_org UNIQUE (organization_id, name)
);

CREATE TABLE chat_tags (
  chat_id uuid NOT NULL,
  tag_id bigint NOT NULL,
  added_by uuid NOT NULL,
  added_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (chat_id, tag_id),
  CONSTRAINT chat_tags_chat_fk FOREIGN KEY (chat_id) REFERENCES chats(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT chat_tags_tag_fk FOREIGN KEY (tag_id) REFERENCES tags(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT chat_tags_added_by_fk FOREIGN KEY (added_by) REFERENCES users(id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE usage_events (
  id bigserial PRIMARY KEY,
  organization_id uuid NOT NULL,
  user_id uuid,
  event_type usage_event_type NOT NULL,
  model_id integer,
  chat_id uuid,
  message_id bigint,
  tokens_in integer NOT NULL DEFAULT 0,
  tokens_out integer NOT NULL DEFAULT 0,
  cost numeric(12,6) NOT NULL DEFAULT 0,
  happened_at timestamptz NOT NULL DEFAULT now(),
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT usage_org_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT usage_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT usage_model_fk FOREIGN KEY (model_id) REFERENCES models(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT usage_chat_fk FOREIGN KEY (chat_id) REFERENCES chats(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT usage_message_fk FOREIGN KEY (message_id) REFERENCES messages(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT usage_tokens_chk CHECK (tokens_in >= 0 AND tokens_out >= 0),
  CONSTRAINT usage_cost_chk CHECK (cost >= 0)
);

CREATE TABLE invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  status invoice_status NOT NULL DEFAULT 'draft',
  period_from date NOT NULL,
  period_to date NOT NULL,
  currency text NOT NULL DEFAULT 'USD',
  amount_total numeric(12,2) NOT NULL DEFAULT 0,
  issued_at timestamptz,
  paid_at timestamptz,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inv_org_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT inv_period_chk CHECK (period_to >= period_from),
  CONSTRAINT inv_amount_chk CHECK (amount_total >= 0),
  CONSTRAINT inv_currency_chk CHECK (char_length(currency) = 3)
);

CREATE TABLE chat_stats (
  chat_id uuid PRIMARY KEY,
  message_count integer NOT NULL DEFAULT 0,
  user_message_count integer NOT NULL DEFAULT 0,
  assistant_message_count integer NOT NULL DEFAULT 0,
  system_message_count integer NOT NULL DEFAULT 0,
  last_message_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chat_stats_chat_fk FOREIGN KEY (chat_id) REFERENCES chats(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT chat_stats_nonneg_chk CHECK (message_count >= 0 AND user_message_count >= 0 AND assistant_message_count >= 0 AND system_message_count >= 0)
);

CREATE TABLE project_stats (
  project_id uuid PRIMARY KEY,
  chat_count integer NOT NULL DEFAULT 0,
  message_count integer NOT NULL DEFAULT 0,
  active_member_count integer NOT NULL DEFAULT 0,
  last_activity_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT project_stats_project_fk FOREIGN KEY (project_id) REFERENCES projects(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT project_stats_nonneg_chk CHECK (chat_count >= 0 AND message_count >= 0 AND active_member_count >= 0)
);

CREATE TABLE audit_log (
  id bigserial PRIMARY KEY,
  table_name text NOT NULL,
  operation text NOT NULL,
  record_pk jsonb NOT NULL,
  old_data jsonb,
  new_data jsonb,
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid,
  txid bigint NOT NULL DEFAULT txid_current(),
  client_addr inet,
  application_name text,
  CONSTRAINT audit_op_chk CHECK (operation IN ('INSERT','UPDATE','DELETE')),
  CONSTRAINT audit_changed_by_fk FOREIGN KEY (changed_by) REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL
);

COMMIT;
