ALTER TABLE users
    ADD COLUMN failed_login_attempts SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN locked_until TIMESTAMPTZ;

CREATE TABLE auth_refresh_tokens (
    id UUID PRIMARY KEY,
    family_id UUID NOT NULL,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash CHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    replaced_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX ix_auth_refresh_tokens_user ON auth_refresh_tokens(user_id);
CREATE INDEX ix_auth_refresh_tokens_family ON auth_refresh_tokens(family_id);

CREATE TABLE auth_audit_logs (
    id UUID PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    username VARCHAR(100) NOT NULL,
    action VARCHAR(50) NOT NULL,
    success BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX ix_auth_audit_logs_user_created ON auth_audit_logs(user_id, created_at);
