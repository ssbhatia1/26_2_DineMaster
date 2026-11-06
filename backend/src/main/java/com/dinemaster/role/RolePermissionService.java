package com.dinemaster.role;

import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class RolePermissionService {
    private final RoleRepository roles;
    private final UserRepository users;

    public RolePermissionService(RoleRepository roles, UserRepository users) {
        this.roles = roles;
        this.users = users;
    }

    @Transactional(readOnly = true)
    public Set<String> permissionsFor(String roleCode) {
        return roles.findByCodeAndActiveTrue(Roles.canonical(roleCode))
                .map(role -> role.getPermissions().stream().map(Permission::getCode).collect(Collectors.toUnmodifiableSet()))
                .orElse(Set.of());
    }

    @Transactional(readOnly = true)
    public Set<String> permissionsFor(String roleCode, Long tenantId) {
        String canonical = Roles.canonical(roleCode);
        return (tenantId == null ? java.util.Optional.<Role>empty()
                : roles.findByCodeAndTenantIdAndActiveTrue(canonical, tenantId))
                .or(() -> roles.findByCodeAndTenantIdIsNullAndActiveTrue(canonical))
                .map(role -> role.getPermissions().stream().map(Permission::getCode)
                        .collect(Collectors.toUnmodifiableSet()))
                .orElse(Set.of());
    }

    @Transactional
    public void replacePermissions(Role role, Set<Permission> permissions) {
        role.setPermissions(permissions);
        roles.save(role);
        for (User user : users.findAll().stream().filter(user -> Roles.matches(user.getRole(), role.getCode())
                && (role.getTenantId() == null || java.util.Objects.equals(user.getTenantId(), role.getTenantId()))).toList()) {
            user.setPermissionVersion(user.getPermissionVersion() + 1);
            users.save(user);
        }
    }
}
