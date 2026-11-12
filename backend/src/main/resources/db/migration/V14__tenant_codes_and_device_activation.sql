ALTER TABLE tenants ADD COLUMN code VARCHAR(60);

UPDATE tenants
SET code = LEFT(TRIM(BOTH '-' FROM REGEXP_REPLACE(UPPER(name), '[^A-Z0-9]+', '-', 'g')), 60)
WHERE code IS NULL;

WITH duplicates AS (
    SELECT id, code, ROW_NUMBER() OVER (PARTITION BY code ORDER BY id) AS ordinal
    FROM tenants
)
UPDATE tenants t
SET code = LEFT(d.code, 40) || '-' || d.id
FROM duplicates d
WHERE t.id = d.id AND d.ordinal > 1;

ALTER TABLE tenants ALTER COLUMN code SET NOT NULL;
ALTER TABLE tenants ADD CONSTRAINT uq_tenants_code UNIQUE (code);

CREATE TABLE auth_device_activations (
    id UUID PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    branch_id BIGINT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    activation_code_hash CHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX ix_device_activations_tenant_branch
    ON auth_device_activations(tenant_id, branch_id, expires_at);

ALTER TABLE auth_devices ADD COLUMN branch_id BIGINT REFERENCES restaurants(id) ON DELETE SET NULL;
ALTER TABLE auth_devices ALTER COLUMN user_id DROP NOT NULL;

INSERT INTO permissions (code, description)
VALUES ('device:activate', 'Issue one-time branch device activation codes')
ON CONFLICT (code) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.code IN ('OWNER', 'MANAGER') AND p.code = 'device:activate'
ON CONFLICT DO NOTHING;
