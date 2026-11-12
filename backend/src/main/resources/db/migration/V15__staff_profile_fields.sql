ALTER TABLE users ADD COLUMN email VARCHAR(255);
ALTER TABLE users ADD COLUMN employee_code VARCHAR(40);
ALTER TABLE users ADD COLUMN joined_on DATE;

CREATE UNIQUE INDEX ux_users_tenant_employee_code
    ON users(tenant_id, employee_code)
    WHERE employee_code IS NOT NULL;
