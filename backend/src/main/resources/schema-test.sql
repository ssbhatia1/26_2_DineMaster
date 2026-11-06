CREATE TABLE IF NOT EXISTS app_seed_state (
    seed_key VARCHAR(100) PRIMARY KEY,
    completed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS user_branches (
    user_id BIGINT NOT NULL,
    branch_id BIGINT NOT NULL,
    assignment_verified BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (user_id, branch_id)
);

CREATE TABLE IF NOT EXISTS user_roles (
    user_id BIGINT NOT NULL,
    role_id BIGINT NOT NULL,
    PRIMARY KEY (user_id, role_id)
);
