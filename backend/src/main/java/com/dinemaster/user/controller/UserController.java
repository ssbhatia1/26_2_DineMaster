package com.dinemaster.user.controller;



import com.dinemaster.role.Roles;
import com.dinemaster.role.RolePermissionService;
import com.dinemaster.security.BranchScopeService;
import com.dinemaster.user.dto.UserBranchUpdateRequest;
import com.dinemaster.user.repository.UserBranchRepository;
import com.dinemaster.user.repository.UserRoleRepository;
import com.dinemaster.role.RoleRepository;
import com.dinemaster.restaurant.repository.RestaurantRepository;
import com.dinemaster.user.dto.UserRequest;
import com.dinemaster.user.dto.UserResponse;
import com.dinemaster.user.dto.PasswordResetRequest;
import com.dinemaster.user.dto.UserDeactivationRequest;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserRepository;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.transaction.annotation.Transactional;
import java.util.Map;
import com.dinemaster.auth.repository.RefreshTokenRepository;
import com.dinemaster.auth.service.AuthAuditService;
import com.dinemaster.auth.dto.AuditLogResponse;
import com.dinemaster.auth.repository.AuthAuditLogRepository;
import com.dinemaster.user.dto.UserRoleUpdateRequest;
import com.dinemaster.user.dto.UserUpdateRequest;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Set;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

@RestController
@RequestMapping("/api/v1/users")
public class UserController {
    private final UserRepository repository;
    private final PasswordEncoder encoder;
    private final RefreshTokenRepository refreshTokens;
    private final AuthAuditService audit;
    private final RolePermissionService rolePermissions;
    private final BranchScopeService branchScope;
    private final UserBranchRepository userBranches;
    private final UserRoleRepository userRoles;
    private final RoleRepository roles;
    private final AuthAuditLogRepository auditLogs;
    private final RestaurantRepository branches;

    public UserController(UserRepository repository, PasswordEncoder encoder, RefreshTokenRepository refreshTokens,
            AuthAuditService audit, RolePermissionService rolePermissions,
            BranchScopeService branchScope, UserBranchRepository userBranches,
            UserRoleRepository userRoles, RoleRepository roles, AuthAuditLogRepository auditLogs,
            RestaurantRepository branches) {
        this.repository = repository;
        this.encoder = encoder;
        this.refreshTokens = refreshTokens;
        this.audit = audit;
        this.rolePermissions = rolePermissions;
        this.branchScope = branchScope;
        this.userBranches = userBranches;
        this.userRoles = userRoles;
        this.roles = roles;
        this.auditLogs = auditLogs;
        this.branches = branches;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('user:view')")
    public ResponseEntity<?> list(Authentication authentication,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) String sort,
            @RequestParam(required = false) String role,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) Long branchId,
            @RequestParam(required = false) String q) {
        User actor = branchScope.requireUser(authentication);
        if (actor.getTenantId() == null) {
            return ResponseEntity.ok(Page.empty(pageRequest(page, size, sort)));
        }

        Boolean active = parseStatus(status);
        String roleFilter = role == null || role.isBlank() ? null : Roles.canonical(role);
        String query = q == null || q.isBlank() ? null : q.trim();
        Pageable pageable = pageRequest(page, size, sort);

        Page<User> users;
        if (Roles.matches(actor.getRole(), "OWNER")) {
            if (branchId != null && !isTenantBranch(actor, branchId)) {
                return ResponseEntity.notFound().build();
            }
            users = repository.searchTenantUsers(actor.getTenantId(), roleFilter, active, branchId, query, pageable);
        } else if (Roles.matches(actor.getRole(), "MANAGER")) {
            List<Long> allowedBranches = userBranches.findBranchIds(actor.getId());
            if (allowedBranches.isEmpty()) return ResponseEntity.ok(Page.empty(pageable));
            if (branchId != null && !allowedBranches.contains(branchId)) {
                return ResponseEntity.notFound().build();
            }
            users = repository.searchTenantUsersInBranches(actor.getTenantId(), allowedBranches,
                    roleFilter, active, branchId, query, pageable);
        } else {
            return ResponseEntity.ok(Page.empty(pageable));
        }
        return ResponseEntity.ok(users.map(user -> userResponse(actor, user)));
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('user:view')")
    public ResponseEntity<?> get(@PathVariable Long id, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        return repository.findById(id).filter(user -> branchScope.canViewUser(actor, user))
                .<ResponseEntity<?>>map(user -> ResponseEntity.ok(userResponse(actor, user)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PostMapping
    @Transactional
    @PreAuthorize("hasAuthority('user:create')")
    public ResponseEntity<?> create(@Valid @RequestBody UserRequest request, Authentication authentication) {
        if (request.password() == null || request.password().isBlank())
            return ResponseEntity.badRequest().body(Map.of("error", "Password is required"));
        if (request.password().length() < 10)
            return ResponseEntity.unprocessableEntity().body(Map.of("error", "Password must be at least 10 characters"));
        User actor = branchScope.requireUser(authentication);
        if (!canManageRole(authentication, request.role()))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot assign this role"));
        if (repository.existsByUsername(request.username().trim()))
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Username already exists"));
        User user = new User();
        copy(request, user, true);
        user.setTenantId(actor.getTenantId());
        user.setMustChangePassword(true);
        List<Long> assignedBranches;
        if (request.branchIds() != null) {
            assignedBranches = request.branchIds().stream().distinct().toList();
        } else {
            assignedBranches = userBranches.findBranchIds(actor.getId());
            // Owners may not have an explicit verified mapping after a security
            // migration. When their tenant has exactly one branch, the intended
            // assignment is unambiguous and can be safely inferred server-side.
            if (assignedBranches.isEmpty() && Roles.matches(actor.getRole(), "OWNER")
                    && actor.getTenantId() != null) {
                List<Long> tenantBranches = branches.findAllByTenantId(actor.getTenantId()).stream()
                        .map(branch -> branch.getId())
                        .toList();
                if (tenantBranches.size() == 1) assignedBranches = tenantBranches;
            }
        }
        if (assignedBranches.isEmpty())
            return ResponseEntity.unprocessableEntity().body(Map.of("error", "Assign the staff member to at least one branch"));
        for (Long branchId : assignedBranches) branchScope.requireBranch(authentication, branchId);
        User saved = repository.save(user);
        userRoles.replaceRole(saved.getId(), saved.getTenantId(), saved.getRole());
        userBranches.replaceBranches(saved.getId(), assignedBranches);
        audit.record(saved.getId(), saved.getUsername(), "USER_CREATED", true,
                actor.getId(), actor.getTenantId(), assignedBranches.get(0), null);
        return ResponseEntity.status(HttpStatus.CREATED).body(
                userResponse(actor, saved));
    }

    @PutMapping("/{id}")
    @Transactional
    @PreAuthorize("hasAuthority('user:update')")
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody UserUpdateRequest request, Authentication authentication) {
        User user = repository.findById(id).orElse(null);
        if (user == null)
            return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!java.util.Objects.equals(user.getTenantId(), actor.getTenantId()))
            return ResponseEntity.notFound().build();
        if (!branchScope.canManageUser(actor, user))
            return ResponseEntity.notFound().build();
        if (!user.getUsername().equals(request.username()) && repository.existsByUsername(request.username().trim()))
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Username already exists"));
        copyProfile(request, user);
        User saved = repository.save(user);
        audit.record(saved.getId(), saved.getUsername(), "USER_UPDATED", true,
                actor.getId(), actor.getTenantId(), null, null);
        return ResponseEntity.ok(userResponse(actor, saved));
    }

    @DeleteMapping("/{id}")
    @Transactional
    @PreAuthorize("hasAuthority('user:deactivate')")
    public ResponseEntity<?> delete(@PathVariable Long id, Authentication authentication) {
        return deactivateUser(id, authentication, null);
    }

    @PostMapping("/{id}/deactivate")
    @Transactional
    @PreAuthorize("hasAuthority('user:deactivate')")
    public ResponseEntity<?> deactivate(@PathVariable Long id,
            @Valid @RequestBody(required = false) UserDeactivationRequest request, Authentication authentication) {
        return deactivateUser(id, authentication, request == null ? null : request.reason());
    }

    @PostMapping("/{id}/reactivate")
    @Transactional
    @PreAuthorize("hasAuthority('user:update')")
    public ResponseEntity<?> reactivate(@PathVariable Long id, Authentication authentication) {
        User user = repository.findById(id).orElse(null);
        if (user == null) return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!java.util.Objects.equals(user.getTenantId(), actor.getTenantId())
                || !branchScope.canManageUser(actor, user)) {
            return ResponseEntity.notFound().build();
        }
        if (!user.isActive()) {
            user.setActive(true);
            user.setPermissionVersion(user.getPermissionVersion() + 1);
            repository.save(user);
            audit.record(user.getId(), user.getUsername(), "USER_REACTIVATE", true,
                    actor.getId(), actor.getTenantId(), null, null);
        }
        return ResponseEntity.ok(userResponse(actor, user));
    }

    @PutMapping("/{id}/roles")
    @Transactional
    @PreAuthorize("hasAuthority('role:assign')")
    public ResponseEntity<?> assignRoles(@PathVariable Long id,
            @Valid @RequestBody UserRoleUpdateRequest request, Authentication authentication) {
        if (request.roleCodes().size() != 1) {
            return ResponseEntity.unprocessableEntity()
                    .body(Map.of("error", "Exactly one role is supported for a staff account"));
        }
        User actor = branchScope.requireUser(authentication);
        User target = repository.findById(id).orElse(null);
        if (target == null || !java.util.Objects.equals(target.getTenantId(), actor.getTenantId())
                || !branchScope.canManageUser(actor, target)) {
            return ResponseEntity.notFound().build();
        }
        String role = Roles.canonical(request.roleCodes().get(0));
        if (isSameUser(authentication, target) || !canManageRole(authentication, role)) {
            return ResponseEntity.status(403).body(Map.of("error", "You cannot assign this role"));
        }
        String previousRole = target.getRole();
        if (!Roles.matches(previousRole, role)) {
            target.setRole(role);
            target.setPermissionVersion(target.getPermissionVersion() + 1);
            repository.save(target);
            userRoles.replaceRoles(target.getId(), target.getTenantId(), List.of(role));
            revokeRefreshTokens(target.getId());
            audit.record(target.getId(), target.getUsername(), "USER_ROLE_CHANGED", true,
                    actor.getId(), actor.getTenantId(), null, previousRole + " -> " + role);
        }
        return ResponseEntity.ok(userResponse(actor, target));
    }

    @GetMapping("/{id}/audit")
    @PreAuthorize("hasAuthority('audit:view')")
    public ResponseEntity<?> audit(@PathVariable Long id, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        User target = repository.findById(id).orElse(null);
        if (target == null || !branchScope.canViewUser(actor, target)) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(auditLogs.findTop100ByUserIdAndTenantIdOrderByCreatedAtDesc(
                id, actor.getTenantId()).stream().map(AuditLogResponse::from).toList());
    }

    @GetMapping("/{id}/sessions")
    @PreAuthorize("hasAuthority('session:revoke')")
    public ResponseEntity<?> sessions(@PathVariable Long id, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        User target = repository.findById(id).orElse(null);
        if (target == null || !branchScope.canViewUser(actor, target)) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(refreshTokens.findAllByUserIdAndRevokedAtIsNull(id).stream()
                .map(token -> {
                    Map<String, Object> session = new java.util.LinkedHashMap<>();
                    session.put("sessionId", token.getId());
                    session.put("deviceId", token.getDeviceId());
                    session.put("createdAt", token.getCreatedAt());
                    session.put("expiresAt", token.getExpiresAt());
                    return session;
                }).toList());
    }

    private ResponseEntity<?> deactivateUser(Long id, Authentication authentication, String reason) {
        User user = repository.findById(id).orElse(null);
        if (user == null)
            return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!java.util.Objects.equals(user.getTenantId(), actor.getTenantId()))
            return ResponseEntity.notFound().build();
        if (!branchScope.canManageUser(actor, user))
            return ResponseEntity.notFound().build();
        if (isSameUser(authentication, user))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot deactivate your own account"));
        if (!canManageRole(authentication, user.getRole()))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot deactivate this role"));
        if (com.dinemaster.role.Roles.matches(user.getRole(), "OWNER")
                && repository.countActiveByRoleAndTenantId("OWNER", user.getTenantId()) <= 1)
            return ResponseEntity.status(409).body(Map.of("error", "The last Restaurant Admin cannot be deactivated"));
        user.setActive(false);
        user.setPermissionVersion(user.getPermissionVersion() + 1);
        repository.save(user);
        audit.record(user.getId(), user.getUsername(), "USER_DEACTIVATE", true,
                actor.getId(), actor.getTenantId(), null, reason);
        revokeRefreshTokens(id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/{id}/reset-password")
    @Transactional
    @PreAuthorize("hasAuthority('role:assign')")
    public ResponseEntity<?> resetPassword(@PathVariable Long id,
            @Valid @RequestBody PasswordResetRequest request, Authentication authentication) {
        User user = repository.findById(id).orElse(null);
        if (user == null) return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!java.util.Objects.equals(user.getTenantId(), actor.getTenantId())) return ResponseEntity.notFound().build();
        if (!branchScope.canManageUser(actor, user)) return ResponseEntity.notFound().build();
        if (isSameUser(authentication, user))
            return ResponseEntity.status(403).body(Map.of("error", "Use the password change endpoint for your own account"));
        if (!canManageRole(authentication, user.getRole()))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot reset this user's password"));
        user.setPassword(encoder.encode(request.temporaryPassword()));
        user.setMustChangePassword(true);
        user.setPermissionVersion(user.getPermissionVersion() + 1);
        repository.save(user);
        audit.record(user.getId(), user.getUsername(), "PASSWORD_RESET", true,
                actor.getId(), actor.getTenantId(), null, null);
        revokeRefreshTokens(id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/{id}/sessions/revoke")
    @Transactional
    @PreAuthorize("hasAuthority('session:revoke')")
    public ResponseEntity<?> revokeSessions(@PathVariable Long id, Authentication authentication) {
        User user = repository.findById(id).orElse(null);
        if (user == null) return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!java.util.Objects.equals(user.getTenantId(), actor.getTenantId())) return ResponseEntity.notFound().build();
        if (!branchScope.canManageUser(actor, user)) return ResponseEntity.notFound().build();
        user.setPermissionVersion(user.getPermissionVersion() + 1);
        repository.save(user);
        revokeRefreshTokens(id);
        audit.record(id, user.getUsername(), "SESSIONS_REVOKED", true,
                actor.getId(), actor.getTenantId(), null, null);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/{id}/sessions")
    @Transactional
    @PreAuthorize("hasAuthority('session:revoke')")
    public ResponseEntity<?> deleteSessions(@PathVariable Long id, Authentication authentication) {
        return revokeSessions(id, authentication);
    }

    @PatchMapping("/{id}/branches")
    @Transactional
    @PreAuthorize("hasAuthority('user:update')")
    public ResponseEntity<?> assignBranches(@PathVariable Long id,
            @Valid @RequestBody UserBranchUpdateRequest request, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        User target = repository.findById(id).orElse(null);
        if (target == null || !java.util.Objects.equals(target.getTenantId(), actor.getTenantId()))
            return ResponseEntity.notFound().build();
        if (!branchScope.canManageUser(actor, target)) return ResponseEntity.notFound().build();
        for (Long branchId : request.branchIds().stream().distinct().toList()) {
            branchScope.requireBranch(authentication, branchId);
        }
        userBranches.replaceBranches(id, request.branchIds());
        target.setPermissionVersion(target.getPermissionVersion() + 1);
        repository.save(target);
        return ResponseEntity.noContent().build();
    }

    private boolean canManageRole(Authentication authentication, String targetRole) {
        User actingUser = branchScope.requireUser(authentication);
        String actor = Roles.canonical(actingUser.getRole());
        String target = com.dinemaster.role.Roles.canonical(targetRole);
        var role = roles.findByCodeAndTenantIdAndActiveTrue(target, actingUser.getTenantId())
                .or(() -> roles.findByCodeAndTenantIdIsNullAndActiveTrue(target)).orElse(null);
        if (role == null) return false;
        if (actor.equals("OWNER")) return !target.equals("SUPER_ADMIN");
        return actor.equals("MANAGER") && role.getTenantId() == null
                && java.util.Set.of("CASHIER", "WAITER", "CHEF", "INVENTORY_MANAGER", "STAFF").contains(target);
    }

    private UserResponse userResponse(User actor, User user) {
        String contact = Roles.matches(actor.getRole(), "OWNER") ? user.getContactDetails() : null;
        return UserResponse.from(user,
                rolePermissions.permissionsFor(user.getRole(), user.getTenantId()), contact,
                userBranches.findBranchIds(user.getId()));
    }

    private boolean isTenantBranch(User actor, Long branchId) {
        return branchScope.belongsToTenant(actor, branchId);
    }

    private Boolean parseStatus(String status) {
        if (status == null || status.isBlank() || status.equalsIgnoreCase("all")) return null;
        if (status.equalsIgnoreCase("active")) return true;
        if (status.equalsIgnoreCase("inactive")) return false;
        throw new IllegalArgumentException("status must be ACTIVE, INACTIVE, or ALL");
    }

    private Pageable pageRequest(int page, int size, String sort) {
        int safePage = Math.max(0, page);
        int safeSize = Math.max(1, Math.min(size, 100));
        String[] parts = sort == null ? new String[0] : sort.split(",", 2);
        String property = parts.length == 0 ? "created_at" : switch (parts[0]) {
            case "name" -> "name";
            case "username" -> "username";
            case "role" -> "role";
            case "createdAt", "created_at" -> "created_at";
            default -> "created_at";
        };
        Sort.Direction direction = parts.length == 2 && parts[1].equalsIgnoreCase("asc")
                ? Sort.Direction.ASC : Sort.Direction.DESC;
        return PageRequest.of(safePage, safeSize, Sort.by(direction, property));
    }

    private void revokeRefreshTokens(Long userId) {
        refreshTokens.findAllByUserIdAndRevokedAtIsNull(userId).forEach(token -> {
            token.setRevokedAt(OffsetDateTime.now());
            refreshTokens.save(token);
        });
    }

    private boolean hasAuthority(Authentication authentication, String authority) {
        return authentication.getAuthorities().stream().anyMatch(a -> a.getAuthority().equals(authority));
    }

    private boolean isSameUser(Authentication authentication, User user) {
        return authentication != null && authentication.getName().equals(user.getUsername());
    }

    private void copy(UserRequest request, User user, boolean requirePassword) {
        user.setName(request.name().trim());
        user.setUsername(request.username().trim());
        user.setRole(Roles.canonical(request.role()));
        if (requirePassword || (request.password() != null && !request.password().isBlank()))
            user.setPassword(encoder.encode(request.password()));
        if (request.active() != null)
            user.setActive(request.active());
        user.setContactDetails(request.contactDetails());
        user.setShiftTiming(request.shiftTiming());
    }

    private void copyProfile(UserUpdateRequest request, User user) {
        user.setName(request.name().trim());
        user.setUsername(request.username().trim());
        user.setContactDetails(request.contactDetails());
        user.setShiftTiming(request.shiftTiming());
    }
}
