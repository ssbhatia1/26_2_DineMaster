package com.dinemaster.config;

import com.dinemaster.role.Permission;
import com.dinemaster.role.PermissionRepository;
import com.dinemaster.role.Role;
import com.dinemaster.role.RolePermissions;
import com.dinemaster.role.RoleRepository;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.jdbc.core.JdbcTemplate;
import java.util.LinkedHashSet;
import java.util.Set;

@Component
public class RolePermissionSeeder implements ApplicationRunner {
    private final RoleRepository roles;
    private final PermissionRepository permissions;
    private final JdbcTemplate jdbc;

    public RolePermissionSeeder(RoleRepository roles, PermissionRepository permissions, JdbcTemplate jdbc) {
        this.roles = roles;
        this.permissions = permissions;
        this.jdbc = jdbc;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        Integer seeded = jdbc.queryForObject("select count(*) from app_seed_state where seed_key = ?",
                Integer.class, "default-role-permissions-v3");
        if (seeded != null && seeded > 0) return;
        for (String roleCode : Set.of("SUPER_ADMIN", "OWNER", "MANAGER", "CASHIER", "WAITER", "CHEF", "INVENTORY_MANAGER", "STAFF")) {
            Role role = roles.findByCodeAndTenantIdIsNullAndActiveTrue(roleCode)
                    .orElseGet(() -> roles.save(new Role(roleCode, roleCode.replace('_', ' '))));
            Set<Permission> grants = new LinkedHashSet<>(role.getPermissions());
            for (String code : RolePermissions.forRole(roleCode)) {
                Permission permission = permissions.findByCode(code).orElseGet(() -> permissions.save(new Permission(code)));
                grants.add(permission);
            }
            role.setPermissions(grants);
            roles.save(role);
        }
        jdbc.update("insert into app_seed_state (seed_key) values (?)", "default-role-permissions-v3");
    }
}
