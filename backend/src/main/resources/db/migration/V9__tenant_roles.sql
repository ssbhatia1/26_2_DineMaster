ALTER TABLE roles ADD COLUMN tenant_id BIGINT REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE roles DROP CONSTRAINT IF EXISTS roles_code_key;
CREATE UNIQUE INDEX ux_roles_system_code ON roles(code) WHERE tenant_id IS NULL;
CREATE UNIQUE INDEX ux_roles_tenant_code ON roles(tenant_id, code) WHERE tenant_id IS NOT NULL;

ALTER TABLE users ALTER COLUMN role TYPE VARCHAR(50);
ALTER TABLE users ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE auth_devices ALTER COLUMN tenant_id DROP NOT NULL;
UPDATE users SET tenant_id = NULL WHERE upper(role) = 'SUPER_ADMIN';
DELETE FROM user_branches WHERE user_id IN (SELECT id FROM users WHERE upper(role) = 'SUPER_ADMIN');

INSERT INTO permissions (code, description) VALUES
    ('tenant:view', 'View tenants'),
    ('tenant:activate', 'Reactivate tenants'),
    ('role:assign', 'Assign and manage roles')
ON CONFLICT (code) DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id)
SELECT roles.id, permissions.id
FROM roles CROSS JOIN permissions
WHERE roles.code = 'SUPER_ADMIN' AND roles.tenant_id IS NULL
  AND permissions.code IN ('tenant:view', 'tenant:activate', 'role:assign')
ON CONFLICT DO NOTHING;

ALTER TABLE customers DROP CONSTRAINT IF EXISTS customers_phone_key;
CREATE UNIQUE INDEX ux_customers_tenant_phone ON customers(tenant_id, phone);
