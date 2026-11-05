package com.dinemaster.user.controller;



import com.dinemaster.role.Roles;
import com.dinemaster.role.RolePermissionService;
import com.dinemaster.security.BranchScopeService;
import com.dinemaster.user.dto.UserBranchUpdateRequest;
import com.dinemaster.user.repository.UserBranchRepository;
import com.dinemaster.user.repository.UserRoleRepository;
import com.dinemaster.role.RoleRepository;
import com.dinemaster.user.dto.UserRequest;
import com.dinemaster.user.dto.UserResponse;
import com.dinemaster.user.dto.PasswordResetRequest;
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
import java.time.OffsetDateTime;

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

    public UserController(UserRepository repository, PasswordEncoder encoder, RefreshTokenRepository refreshTokens,
            AuthAuditService audit, RolePermissionService rolePermissions,
            BranchScopeService branchScope, UserBranchRepository userBranches,
            UserRoleRepository userRoles, RoleRepository roles) {
        this.repository = repository;
        this.encoder = encoder;
        this.refreshTokens = refreshTokens;
        this.audit = audit;
        this.rolePermissions = rolePermissions;
        this.branchScope = branchScope;
        this.userBranches = userBranches;
        this.userRoles = userRoles;
        this.roles = roles;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('user:view')")
    public java.util.List<UserResponse> list(Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        return repository.findAll().stream().filter(user -> java.util.Objects.equals(user.getTenantId(), actor.getTenantId()))
                .map(user -> UserResponse.from(user, rolePermissions.permissionsFor(user.getRole(), user.getTenantId()))).toList();
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('user:view')")
    public ResponseEntity<?> get(@PathVariable Long id, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        return repository.findById(id).filter(user -> java.util.Objects.equals(user.getTenantId(), actor.getTenantId()))
                .<ResponseEntity<?>>map(user -> ResponseEntity.ok(
                UserResponse.from(user, rolePermissions.permissionsFor(user.getRole(), user.getTenantId()))))
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
        User saved = repository.save(user);
        userRoles.replaceRole(saved.getId(), saved.getTenantId(), saved.getRole());
        userBranches.replaceBranches(saved.getId(), userBranches.findBranchIds(actor.getId()));
        audit.record(saved.getId(), saved.getUsername(), "USER_CREATED", true);
        return ResponseEntity.status(HttpStatus.CREATED).body(
                UserResponse.from(saved, rolePermissions.permissionsFor(saved.getRole(), saved.getTenantId())));
    }

    @PutMapping("/{id}")
    @Transactional
    @PreAuthorize("hasAuthority('user:update')")
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody UserRequest request, Authentication authentication) {
        User user = repository.findById(id).orElse(null);
        if (user == null)
            return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!java.util.Objects.equals(user.getTenantId(), actor.getTenantId()))
            return ResponseEntity.notFound().build();
        boolean changingActive = request.active() != null && request.active() != user.isActive();
        boolean deactivating = user.isActive() && Boolean.FALSE.equals(request.active());
        if (changingActive && !hasAuthority(authentication, "user:deactivate"))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot change the user's active status"));
        if (deactivating && isSameUser(authentication, user))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot deactivate your own account"));
        if (deactivating && Roles.matches(user.getRole(), "OWNER")
                && repository.countActiveByRoleAndTenantId("OWNER", user.getTenantId()) <= 1)
            return ResponseEntity.status(409).body(Map.of("error", "The last Restaurant Admin cannot be deactivated"));
        if (changingActive) user.setPermissionVersion(user.getPermissionVersion() + 1);
        boolean selfUpdate = isSameUser(authentication, user);
        if (selfUpdate && !com.dinemaster.role.Roles.matches(user.getRole(), request.role()))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot change your own role"));
        if (request.password() != null && !request.password().isBlank() && request.password().length() < 10)
            return ResponseEntity.unprocessableEntity().body(Map.of("error", "Password must be at least 10 characters"));
        if (!com.dinemaster.role.Roles.matches(user.getRole(), request.role())
                && !hasAuthority(authentication, "role:assign"))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot assign roles"));
        if (!canManageRole(authentication, request.role()))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot assign this role"));
        if (!user.getUsername().equals(request.username()) && repository.existsByUsername(request.username().trim()))
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Username already exists"));
        String previousRole = user.getRole();
        copy(request, user, false);
        if (!Roles.matches(previousRole, user.getRole())) {
            user.setPermissionVersion(user.getPermissionVersion() + 1);
        }
        User saved = repository.save(user);
        if (!Roles.matches(previousRole, saved.getRole()))
            userRoles.replaceRole(saved.getId(), saved.getTenantId(), saved.getRole());
        if (!com.dinemaster.role.Roles.matches(previousRole, saved.getRole()))
            audit.record(saved.getId(), saved.getUsername(), "USER_ROLE_CHANGED", true);
        if (deactivating) {
            audit.record(saved.getId(), saved.getUsername(), "USER_DEACTIVATE", true);
            revokeRefreshTokens(saved.getId());
        }
        return ResponseEntity.ok(UserResponse.from(saved, rolePermissions.permissionsFor(saved.getRole(), saved.getTenantId())));
    }

    @DeleteMapping("/{id}")
    @Transactional
    @PreAuthorize("hasAuthority('user:deactivate')")
    public ResponseEntity<?> delete(@PathVariable Long id, Authentication authentication) {
        return deactivateUser(id, authentication);
    }

    @PostMapping("/{id}/deactivate")
    @Transactional
    @PreAuthorize("hasAuthority('user:deactivate')")
    public ResponseEntity<?> deactivate(@PathVariable Long id, Authentication authentication) {
        return deactivateUser(id, authentication);
    }

    private ResponseEntity<?> deactivateUser(Long id, Authentication authentication) {
        User user = repository.findById(id).orElse(null);
        if (user == null)
            return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!java.util.Objects.equals(user.getTenantId(), actor.getTenantId()))
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
        audit.record(user.getId(), user.getUsername(), "USER_DEACTIVATE", true);
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
        if (isSameUser(authentication, user))
            return ResponseEntity.status(403).body(Map.of("error", "Use the password change endpoint for your own account"));
        if (!canManageRole(authentication, user.getRole()))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot reset this user's password"));
        user.setPassword(encoder.encode(request.temporaryPassword()));
        user.setPermissionVersion(user.getPermissionVersion() + 1);
        repository.save(user);
        audit.record(user.getId(), user.getUsername(), "PASSWORD_RESET", true);
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
        user.setPermissionVersion(user.getPermissionVersion() + 1);
        repository.save(user);
        revokeRefreshTokens(id);
        audit.record(id, user.getUsername(), "SESSIONS_REVOKED", true);
        return ResponseEntity.noContent().build();
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
}
