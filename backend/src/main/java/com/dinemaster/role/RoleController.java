package com.dinemaster.role;

import com.dinemaster.role.dto.RolePermissionUpdateRequest;
import com.dinemaster.role.dto.RoleCreateRequest;
import com.dinemaster.security.BranchScopeService;
import com.dinemaster.user.entity.User;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.security.core.Authentication;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/roles")
public class RoleController {
    private final RoleRepository roles;
    private final PermissionRepository permissions;
    private final RolePermissionService rolePermissionService;
    private final BranchScopeService branchScope;

    public RoleController(RoleRepository roles, PermissionRepository permissions,
            RolePermissionService rolePermissionService, BranchScopeService branchScope) {
        this.roles = roles; this.permissions = permissions; this.rolePermissionService = rolePermissionService;
        this.branchScope = branchScope;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('role:assign')")
    public java.util.List<Map<String, Object>> list(Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        return roles.findAllByTenantIdIsNullOrTenantIdOrderByCode(actor.getTenantId()).stream().map(role -> Map.<String, Object>of(
                "code", role.getCode(), "name", role.getName(),
                "permissions", rolePermissionService.permissionsFor(role.getCode(), actor.getTenantId()))).toList();
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('role:view') or hasAuthority('role:assign')")
    public ResponseEntity<?> get(@PathVariable Long id, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        Role role = roles.findById(id).filter(Role::isActive)
                .filter(value -> value.getTenantId() == null
                        || java.util.Objects.equals(value.getTenantId(), actor.getTenantId()))
                .orElse(null);
        if (role == null) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(Map.of(
                "id", role.getId(),
                "code", role.getCode(),
                "name", role.getName(),
                "permissions", role.getPermissions().stream().map(Permission::getCode).sorted().toList()));
    }

    @GetMapping("/permissions")
    @PreAuthorize("hasAuthority('role:assign')")
    public java.util.List<String> permissionCodes() {
        return permissions.findAll().stream().map(Permission::getCode).sorted().toList();
    }

    @PostMapping
    @PreAuthorize("hasAuthority('role:assign')")
    public ResponseEntity<?> create(@Valid @RequestBody RoleCreateRequest request, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        if (actor.getTenantId() == null) {
            return ResponseEntity.status(403).body(Map.of("error", "A tenant is required to create a custom role"));
        }
        String code = com.dinemaster.role.Roles.canonical(request.code());
        if (roles.findByCodeAndTenantIdAndActiveTrue(code, actor.getTenantId()).isPresent()
                || roles.findByCodeAndTenantIdIsNullAndActiveTrue(code).isPresent()) {
            return ResponseEntity.status(409).body(Map.of("error", "Role code already exists"));
        }
        Set<String> requested = request.permissions() == null ? Set.of()
                : request.permissions().stream().map(String::trim).collect(Collectors.toSet());
        Set<Permission> grants = findPermissions(requested);
        if (grants.size() != requested.size()) {
            return ResponseEntity.badRequest().body(Map.of("error", "One or more permission codes do not exist"));
        }
        if (containsPlatformPermission(requested)) {
            return ResponseEntity.status(403).body(Map.of("error", "Tenant roles cannot receive platform permissions"));
        }
        Role role = new Role(code, request.name().trim(), actor.getTenantId());
        role.setPermissions(grants);
        roles.save(role);
        return ResponseEntity.status(201).body(Map.of("code", code, "name", role.getName(), "permissions", requested));
    }

    @PatchMapping("/{roleCode}/permissions")
    @PreAuthorize("hasAuthority('role:assign')")
    public ResponseEntity<?> replacePermissions(@PathVariable String roleCode,
            @Valid @RequestBody RolePermissionUpdateRequest request, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        String code = com.dinemaster.role.Roles.canonical(roleCode);
        Role role = roles.findByCodeAndTenantIdAndActiveTrue(code, actor.getTenantId()).orElse(null);
        if (role == null && "SUPER_ADMIN".equals(com.dinemaster.role.Roles.canonical(actor.getRole()))) {
            role = roles.findByCodeAndTenantIdIsNullAndActiveTrue(code).orElse(null);
        }
        if (role == null) return ResponseEntity.notFound().build();
        Set<String> requested = request.permissions().stream().map(String::trim).collect(Collectors.toSet());
        Set<Permission> grants = findPermissions(requested);
        if (grants.size() != requested.size()) {
            return ResponseEntity.badRequest().body(Map.of("error", "One or more permission codes do not exist"));
        }
        if (role.getTenantId() != null && containsPlatformPermission(requested)) {
            return ResponseEntity.status(403).body(Map.of("error", "Tenant roles cannot receive platform permissions"));
        }
        rolePermissionService.replacePermissions(role, grants);
        return ResponseEntity.ok(Map.of("role", role.getCode(), "permissions", requested));
    }

    private Set<Permission> findPermissions(Set<String> requested) {
        return permissions.findAll().stream().filter(permission -> requested.contains(permission.getCode()))
                .collect(Collectors.toSet());
    }

    private boolean containsPlatformPermission(Set<String> codes) {
        return codes.stream().anyMatch(code -> code.startsWith("tenant:")
                || code.startsWith("licence:") || code.startsWith("support:"));
    }
}
