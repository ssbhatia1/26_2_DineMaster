ALTER TABLE users
    ADD COLUMN must_change_password BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE auth_audit_logs
    ADD COLUMN actor_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN tenant_id BIGINT REFERENCES tenants(id) ON DELETE SET NULL,
    ADD COLUMN branch_id BIGINT REFERENCES restaurants(id) ON DELETE SET NULL,
    ADD COLUMN reason VARCHAR(500);

CREATE INDEX ix_auth_audit_logs_tenant_created
    ON auth_audit_logs(tenant_id, created_at DESC);
