package com.dinemaster.user.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class UserRoleRepository {
    private final JdbcTemplate jdbc;

    public UserRoleRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public void replaceRole(Long userId, Long tenantId, String code) {
        jdbc.update("delete from user_roles where user_id = ?", userId);
        int assigned = jdbc.update("""
                insert into user_roles (user_id, role_id)
                select ?, id from roles
                where code = ? and (tenant_id = ? or tenant_id is null)
                order by tenant_id nulls last limit 1
                """, userId, code, tenantId);
        if (assigned != 1) throw new IllegalArgumentException("Role is not available for this tenant");
    }

    public java.util.Optional<String> findRoleCode(Long userId) {
        return jdbc.query("select roles.code from user_roles join roles on roles.id = user_roles.role_id where user_roles.user_id = ? and roles.active = true",
                rs -> rs.next() ? java.util.Optional.of(rs.getString(1)) : java.util.Optional.empty(), userId);
    }
}
