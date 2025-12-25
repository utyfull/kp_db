SET search_path = clown_gpt, public;

INSERT INTO models(name, provider, version, context_window, is_active, price_input_1k, price_output_1k, capabilities)
VALUES
('clown 1.2','clown','1.2',8192,true,0,0,'{}'::jsonb),
('clown 1.3','clown','1.3',16384,true,0,0,'{}'::jsonb),
('clown 1.4','clown','1.4',32768,true,0,0,'{}'::jsonb);

INSERT INTO users(username, email, password_hash, role, is_active, email_verified, settings)
VALUES ('admin','admin@clown.local',crypt('admin', gen_salt('bf')),'admin',true,true,'{"theme":"dark"}'::jsonb);

INSERT INTO user_profiles(user_id, display_name, bio, locale, timezone, preferences)
SELECT id, 'admin', 'Demo admin', 'ru-RU', 'Europe/Moscow', '{"darkOnly":true}'::jsonb
FROM users WHERE username='admin';

-- seed personal org for admin with default plan
INSERT INTO organizations(slug, name, owner_user_id, billing_email, plan, is_active, created_at, updated_at, settings)
SELECT lower(username), username || ' org', id, email, 'free', true, now(), now(), '{"darkOnly":true}'::jsonb
FROM users
WHERE username='admin'
ON CONFLICT DO NOTHING;

INSERT INTO organization_members(organization_id, user_id, member_role, can_billing, joined_at, invited_by, is_active)
SELECT organizations.id, users.id, 'owner', true, now(), NULL, true
FROM organizations
JOIN users ON organizations.owner_user_id = users.id
WHERE users.username = 'admin'
ON CONFLICT DO NOTHING;
