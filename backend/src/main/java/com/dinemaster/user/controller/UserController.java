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
import com.dinemaster.user.dto.UserRoleUpdateRequest;
import com.dinemaster.user.dto.UserLifecycleRequest;
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
import com.dinemaster.auth.repository.AuthAuditLogRepository;
import com.dinemaster.auth.dto.AuditLogResponse;
import com.dinemaster.auth.service.AuthAuditService;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Set;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import java.text.Normalizer;

@RestController
@RequestMapping({"/api/v1/admin/staff", "/api/v1/users"})
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

    public UserController(UserRepository repository, PasswordEncoder encoder, RefreshTokenRepository refreshTokens,
            AuthAuditService audit, RolePermissionService rolePermissions,
            BranchScopeService branchScope, UserBranchRepository userBranches,
            UserRoleRepository userRoles, RoleRepository roles, AuthAuditLogRepository auditLogs) {
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
    }

    @GetMapping
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('user:view')")
    public ResponseEntity<?> list(Authentication authentication,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(defaultValue = "createdAt,desc") String sort,
            @RequestParam(required = false) String role,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) Long branchId,
            @RequestParam(required = false, name = "q") String query) {
        User actor = branchScope.requireUser(authentication);
        if (page < 0 || size < 1 || size > 100) return ResponseEntity.badRequest().body(Map.of("error", "Invalid page or size"));
        Boolean active = switch (status == null ? "" : status.toUpperCase(java.util.Locale.ROOT)) {
            case "ACTIVE" -> true;
            case "INACTIVE" -> false;
            case "" -> null;
            default -> null;
        };
        if (status != null && !Set.of("ACTIVE", "INACTIVE").contains(status.toUpperCase(java.util.Locale.ROOT)))
            return ResponseEntity.badRequest().body(Map.of("error", "status must be ACTIVE or INACTIVE"));
        String[] sortParts = sort.split(",");
        Set<String> allowedSorts = Set.of("createdAt", "name", "username", "role");
        if (sortParts.length != 2 || !allowedSorts.contains(sortParts[0])
                || !(sortParts[1].equalsIgnoreCase("asc") || sortParts[1].equalsIgnoreCase("desc")))
            return ResponseEntity.badRequest().body(Map.of("error", "Unsupported sort"));
        Sort.Direction direction = Sort.Direction.fromString(sortParts[1]);
        String databaseSort = switch (sortParts[0]) {
            case "createdAt" -> "created_at";
            default -> sortParts[0];
        };
        Pageable pageable = PageRequest.of(page, size, Sort.by(direction, databaseSort));
        if (branchId != null) {
            try { branchScope.requireBranch(authentication, branchId); }
            catch (org.springframework.security.access.AccessDeniedException denied) { return ResponseEntity.notFound().build(); }
        }
        Page<User> results;
        if (Roles.matches(actor.getRole(), "MANAGER")) {
            List<Long> visibleBranches = userBranches.findBranchIds(actor.getId());
            if (visibleBranches.isEmpty()) results = Page.empty(pageable);
            else results = repository.searchTenantUsersInBranches(actor.getTenantId(), visibleBranches,
                    role, active, branchId, normalizeQuery(query), pageable);
        } else {
            results = repository.searchTenantUsers(actor.getTenantId(), role, active, branchId,
                    normalizeQuery(query), pageable);
        }
        return ResponseEntity.ok(Map.of("content", results.getContent().stream().map(user ->
                        UserResponse.from(user, rolePermissions.permissionsFor(user.getRole(), user.getTenantId()),
                                visibleContact(actor, user), userBranches.findBranchIds(user.getId())))
                        .toList(), "page", results.getNumber(), "size", results.getSize(),
                "totalElements", results.getTotalElements(), "totalPages", results.getTotalPages()));
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('user:view')")
    public ResponseEntity<?> get(@PathVariable Long id, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        return repository.findById(id).filter(user -> branchScope.canViewUser(actor, user))
                .<ResponseEntity<?>>map(user -> ResponseEntity.ok(
                UserResponse.from(user, rolePermissions.permissionsFor(user.getRole(), user.getTenantId()),
                        visibleContact(actor, user), userBranches.findBranchIds(user.getId()))))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PostMapping
    @Transactional
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('user:create')")
    public ResponseEntity<?> create(@Valid @RequestBody UserRequest request, Authentication authentication) {
        if (request.effectiveRole() == null)
            return ResponseEntity.badRequest().body(Map.of("error", "Assign exactly one roleCode"));
        if (request.password() == null || request.password().isBlank())
            return ResponseEntity.badRequest().body(Map.of("error", "Password is required"));
        if (request.password().length() < 10)
            return ResponseEntity.unprocessableEntity().body(Map.of("error", "Password must be at least 10 characters"));
        User actor = branchScope.requireUser(authentication);
        List<Long> assignedBranches = request.branchIds() == null || request.branchIds().isEmpty()
                ? userBranches.findBranchIds(actor.getId()) : request.branchIds().stream().distinct().toList();
        if (assignedBranches.isEmpty()) return ResponseEntity.badRequest().body(Map.of("error", "Assign at least one branch"));
        if (Roles.matches(actor.getRole(), "MANAGER") && assignedBranches.size() != 1)
            return ResponseEntity.status(403).body(Map.of("error", "Managers can assign staff only to their branch"));
        try { for (Long branch : assignedBranches) branchScope.requireBranch(authentication, branch); }
        catch (org.springframework.security.access.AccessDeniedException denied) { return ResponseEntity.notFound().build(); }
        if (!canManageRole(authentication, request.effectiveRole()))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot assign this role"));
        if (repository.existsByUsername(request.username().trim()))
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Username already exists"));
        if (request.employeeCode() != null && !request.employeeCode().isBlank()
                && repository.existsByTenantIdAndEmployeeCode(actor.getTenantId(), request.employeeCode().trim()))
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Employee code already exists"));
        User user = new User();
        copy(request, user, true);
        user.setTenantId(actor.getTenantId());
        user.setMustChangePassword(true);
        User saved = repository.save(user);
        userRoles.replaceRole(saved.getId(), saved.getTenantId(), saved.getRole());
        userBranches.replaceBranches(saved.getId(), assignedBranches);
        audit.record(saved.getId(), saved.getUsername(), "USER_CREATED", true, actor.getId(), actor.getTenantId(),
                assignedBranches.get(0), null);
        return ResponseEntity.status(HttpStatus.CREATED).body(
                UserResponse.from(saved, rolePermissions.permissionsFor(saved.getRole(), saved.getTenantId()),
                        visibleContact(actor, saved), userBranches.findBranchIds(saved.getId())));
    }

    @PutMapping("/{id}")
    @Transactional
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('user:update')")
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody UserRequest request, Authentication authentication) {
        User user = repository.findById(id).orElse(null);
        if (user == null)
            return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!java.util.Objects.equals(user.getTenantId(), actor.getTenantId()))
            return ResponseEntity.notFound().build();
        if (!branchScope.canManageUser(actor, user)) return ResponseEntity.notFound().build();
        if (request.password() != null && !request.password().isBlank())
            return ResponseEntity.badRequest().body(Map.of("error", "Use the reset-password endpoint to change a password"));
        if (request.active() != null || request.branchIds() != null)
            return ResponseEntity.badRequest().body(Map.of("error", "Use the dedicated status and branches endpoints"));
        String requestedRole = request.effectiveRole();
        if (requestedRole != null && !Roles.matches(user.getRole(), requestedRole))
            return ResponseEntity.badRequest().body(Map.of("error", "Use the roles endpoint to change roles"));
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
        if (requestedRole != null && selfUpdate && !com.dinemaster.role.Roles.matches(user.getRole(), requestedRole))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot change your own role"));
        if (requestedRole != null && !com.dinemaster.role.Roles.matches(user.getRole(), requestedRole)
                && !hasAuthority(authentication, "role:assign"))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot assign roles"));
        if (requestedRole != null && !canManageRole(authentication, requestedRole))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot assign this role"));
        if (!user.getUsername().equals(request.username()) && repository.existsByUsername(request.username().trim()))
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Username already exists"));
        if (request.employeeCode() != null && !request.employeeCode().equals(user.getEmployeeCode())
                && repository.existsByTenantIdAndEmployeeCode(actor.getTenantId(), request.employeeCode().trim()))
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Employee code already exists"));
        String previousRole = user.getRole();
        copy(request, user, false);
        if (requestedRole != null && !Roles.matches(previousRole, user.getRole())) {
            user.setPermissionVersion(user.getPermissionVersion() + 1);
        }
        User saved = repository.save(user);
        if (requestedRole != null && !Roles.matches(previousRole, saved.getRole()))
            userRoles.replaceRole(saved.getId(), saved.getTenantId(), saved.getRole());
        if (!com.dinemaster.role.Roles.matches(previousRole, saved.getRole()))
            audit.record(saved.getId(), saved.getUsername(), "USER_ROLE_CHANGED", true,
                    actor.getId(), actor.getTenantId(), null, previousRole + " -> " + saved.getRole());
        else audit.record(saved.getId(), saved.getUsername(), "USER_UPDATED", true,
                actor.getId(), actor.getTenantId(), null, null);
        if (deactivating) {
            audit.record(saved.getId(), saved.getUsername(), "USER_DEACTIVATE", true);
            revokeRefreshTokens(saved.getId());
        }
        return ResponseEntity.ok(UserResponse.from(saved, rolePermissions.permissionsFor(saved.getRole(), saved.getTenantId()),
                visibleContact(actor, saved), userBranches.findBranchIds(saved.getId())));
    }

    @DeleteMapping("/{id}")
    @Transactional
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('user:deactivate')")
    public ResponseEntity<?> delete(@PathVariable Long id, Authentication authentication) {
        return deactivateUser(id, authentication, null);
    }

    @PostMapping("/{id}/deactivate")
    @Transactional
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('user:deactivate')")
    public ResponseEntity<?> deactivate(@PathVariable Long id,
            @RequestBody(required = false) @Valid UserLifecycleRequest request, Authentication authentication) {
        return deactivateUser(id, authentication, request == null ? null : request.reason());
    }

    private ResponseEntity<?> deactivateUser(Long id, Authentication authentication, String reason) {
        User user = repository.findById(id).orElse(null);
        if (user == null)
            return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!java.util.Objects.equals(user.getTenantId(), actor.getTenantId()))
            return ResponseEntity.notFound().build();
        if (!branchScope.canManageUser(actor, user)) return ResponseEntity.notFound().build();
        if (isSameUser(authentication, user))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot deactivate your own account"));
        if (!branchScope.canManageUser(actor, user))
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

    @PostMapping("/{id}/reactivate")
    @Transactional
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('user:update')")
    public ResponseEntity<?> reactivate(@PathVariable Long id,
            @RequestBody(required = false) @Valid UserLifecycleRequest request, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        User target = repository.findById(id).filter(user -> branchScope.canManageUser(actor, user)).orElse(null);
        if (target == null) return ResponseEntity.notFound().build();
        if (!target.isActive()) {
            target.setActive(true);
            target.setPermissionVersion(target.getPermissionVersion() + 1);
            repository.save(target);
            audit.record(id, target.getUsername(), "USER_REACTIVATE", true, actor.getId(), actor.getTenantId(), null,
                    request == null ? null : request.reason());
        }
        return ResponseEntity.ok(Map.of("id", target.getId(), "status", "ACTIVE"));
    }

    @PutMapping("/{id}/roles")
    @Transactional
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('role:assign')")
    public ResponseEntity<?> assignRoles(@PathVariable Long id, @Valid @RequestBody UserRoleUpdateRequest request,
            Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        User target = repository.findById(id).filter(user -> branchScope.canManageUser(actor, user)).orElse(null);
        if (target == null) return ResponseEntity.notFound().build();
        List<String> codes = request.roleCodes().stream().map(Roles::canonical).distinct().toList();
        // Current identity model resolves one effective role per account.
        if (codes.size() != 1 || !canManageRole(authentication, codes.get(0)))
            return ResponseEntity.status(403).body(Map.of("error", "Requested role assignment is not allowed"));
        String previous = target.getRole();
        target.setRole(codes.get(0));
        target.setPermissionVersion(target.getPermissionVersion() + 1);
        userRoles.replaceRoles(id, target.getTenantId(), codes);
        repository.save(target);
        audit.record(id, target.getUsername(), "USER_ROLE_CHANGED", true, actor.getId(), actor.getTenantId(), null,
                previous + " -> " + codes.get(0));
        revokeRefreshTokens(id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/{id}/reset-password")
    @Transactional
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('user:update')")
    public ResponseEntity<?> resetPassword(@PathVariable Long id,
            @Valid @RequestBody PasswordResetRequest request, Authentication authentication) {
        User user = repository.findById(id).orElse(null);
        if (user == null) return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!branchScope.canManageUser(actor, user)) return ResponseEntity.notFound().build();
        if (isSameUser(authentication, user))
            return ResponseEntity.status(403).body(Map.of("error", "Use the password change endpoint for your own account"));
        if (!canManageRole(authentication, user.getRole()))
            return ResponseEntity.status(403).body(Map.of("error", "You cannot reset this user's password"));
        user.setPassword(encoder.encode(request.temporaryPassword()));
        user.setMustChangePassword(true);
        user.setPermissionVersion(user.getPermissionVersion() + 1);
        repository.save(user);
        audit.record(user.getId(), user.getUsername(), "PASSWORD_RESET", true, actor.getId(), actor.getTenantId(),
                null, request.reason());
        revokeRefreshTokens(id);
        return ResponseEntity.ok(Map.of("userId", id, "resetInitiated", true, "mustChangePassword", true));
    }

    @PostMapping("/{id}/sessions/revoke")
    @DeleteMapping("/{id}/sessions")
    @Transactional
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('session:revoke')")
    public ResponseEntity<?> revokeSessions(@PathVariable Long id, Authentication authentication) {
        User user = repository.findById(id).orElse(null);
        if (user == null) return ResponseEntity.notFound().build();
        User actor = branchScope.requireUser(authentication);
        if (!branchScope.canManageUser(actor, user)) return ResponseEntity.notFound().build();
        user.setPermissionVersion(user.getPermissionVersion() + 1);
        repository.save(user);
        revokeRefreshTokens(id);
        audit.record(id, user.getUsername(), "SESSIONS_REVOKED", true, actor.getId(), actor.getTenantId(), null, null);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{id}/sessions")
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('session:revoke')")
    public ResponseEntity<?> sessions(@PathVariable Long id, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        User target = repository.findById(id).filter(user -> branchScope.canManageUser(actor, user)).orElse(null);
        if (target == null) return ResponseEntity.notFound().build();
        OffsetDateTime now = OffsetDateTime.now();
        return ResponseEntity.ok(refreshTokens.findAllByUserIdAndRevokedAtIsNull(id).stream()
                .filter(token -> token.getExpiresAt().isAfter(now))
                .map(token -> Map.of("sessionId", token.getId().toString(),
                        "deviceId", token.getDeviceId() == null ? "" : token.getDeviceId().toString(),
                        "createdAt", token.getCreatedAt(), "expiresAt", token.getExpiresAt()))
                .toList());
    }

    @GetMapping("/{id}/audit")
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('audit:view')")
    public ResponseEntity<?> auditHistory(@PathVariable Long id, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        User target = repository.findById(id).filter(user -> branchScope.canViewUser(actor, user)).orElse(null);
        if (target == null) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(auditLogs.findTop100ByUserIdAndTenantIdOrderByCreatedAtDesc(id, actor.getTenantId())
                .stream().map(AuditLogResponse::from).toList());
    }

    @PatchMapping("/{id}/branches")
    @PutMapping("/{id}/branches")
    @Transactional
    @PreAuthorize("hasAnyRole('OWNER','MANAGER') and hasAuthority('user:update')")
    public ResponseEntity<?> assignBranches(@PathVariable Long id,
            @Valid @RequestBody UserBranchUpdateRequest request, Authentication authentication) {
        User actor = branchScope.requireUser(authentication);
        User target = repository.findById(id).orElse(null);
        if (target == null || !java.util.Objects.equals(target.getTenantId(), actor.getTenantId()))
            return ResponseEntity.notFound().build();
        if (!branchScope.canManageUser(actor, target)) return ResponseEntity.notFound().build();
        if (Roles.matches(actor.getRole(), "MANAGER") && request.branchIds().size() != 1)
            return ResponseEntity.status(403).body(Map.of("error", "Managers may assign staff only to their branch"));
        try {
            for (Long branchId : request.branchIds().stream().distinct().toList())
                branchScope.requireBranch(authentication, branchId);
        } catch (org.springframework.security.access.AccessDeniedException denied) {
            return ResponseEntity.notFound().build();
        }
        userBranches.replaceBranches(id, request.branchIds());
        target.setPermissionVersion(target.getPermissionVersion() + 1);
        repository.save(target);
        audit.record(id, target.getUsername(), "USER_BRANCHES_CHANGED", true, actor.getId(), actor.getTenantId(),
                request.branchIds().isEmpty() ? null : request.branchIds().get(0), request.branchIds().toString());
        revokeRefreshTokens(id);
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
        if (request.effectiveRole() != null) user.setRole(Roles.canonical(request.effectiveRole()));
        if (requirePassword || (request.password() != null && !request.password().isBlank()))
            user.setPassword(encoder.encode(request.password()));
        if (request.active() != null)
            user.setActive(request.active());
        user.setContactDetails(request.effectiveContactDetails());
        user.setShiftTiming(request.shiftTiming());
        user.setEmail(request.email());
        user.setEmployeeCode(request.employeeCode());
        user.setJoinedOn(request.joinedOn());
    }

    private String normalizeQuery(String value) {
        if (value == null || value.isBlank()) return null;
        return Normalizer.normalize(value.trim(), Normalizer.Form.NFKC);
    }

    private String visibleContact(User actor, User target) {
        String contact = target.getContactDetails();
        if (contact == null || Roles.matches(actor.getRole(), "OWNER")) return contact;
        String digits = contact.replaceAll("\\D", "");
        if (digits.length() < 4) return "****";
        return "******" + digits.substring(digits.length() - 4);
    }
}
