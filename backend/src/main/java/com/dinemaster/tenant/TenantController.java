package com.dinemaster.tenant;

import com.dinemaster.auth.service.AuthAuditService;
import com.dinemaster.tenant.dto.TenantCreateRequest;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserBranchRepository;
import com.dinemaster.user.repository.UserRepository;
import com.dinemaster.user.repository.UserRoleRepository;
import com.dinemaster.auth.repository.RefreshTokenRepository;
import com.dinemaster.auth.repository.AuthDeviceRepository;
import java.time.OffsetDateTime;
import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.security.core.Authentication;

@RestController
@RequestMapping("/api/v1/tenants")
public class TenantController {
    private final TenantRepository tenants;
    private final UserRepository users;
    private final UserBranchRepository userBranches;
    private final UserRoleRepository userRoles;
    private final PasswordEncoder passwordEncoder;
    private final AuthAuditService audit;
    private final RefreshTokenRepository refreshTokens;
    private final AuthDeviceRepository devices;

    public TenantController(TenantRepository tenants, UserRepository users,
            UserBranchRepository userBranches, UserRoleRepository userRoles,
            PasswordEncoder passwordEncoder, AuthAuditService audit,
            RefreshTokenRepository refreshTokens, AuthDeviceRepository devices) {
        this.tenants = tenants;
        this.users = users;
        this.userBranches = userBranches;
        this.userRoles = userRoles;
        this.passwordEncoder = passwordEncoder;
        this.audit = audit;
        this.refreshTokens = refreshTokens;
        this.devices = devices;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('tenant:view')")
    public java.util.List<Tenant> list() {
        return tenants.findAll();
    }

    @PostMapping
    @Transactional
    @PreAuthorize("hasAuthority('tenant:create')")
    public ResponseEntity<?> create(@Valid @RequestBody TenantCreateRequest request, Authentication authentication) {
        String username = request.ownerUsername().trim();
        if (users.existsByUsername(username)) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Username already exists"));
        }

        Tenant tenant = tenants.save(new Tenant(request.name().trim()));
        User owner = new User();
        owner.setName(request.ownerName().trim());
        owner.setUsername(username);
        owner.setPassword(passwordEncoder.encode(request.ownerPassword()));
        owner.setRole("OWNER");
        owner.setTenantId(tenant.getId());
        owner.setActive(true);
        User savedOwner = users.save(owner);
        userRoles.replaceRole(savedOwner.getId(), tenant.getId(), "OWNER");
        userBranches.replaceBranches(savedOwner.getId(), java.util.List.of());
        audit.record(null, authentication.getName(), "TENANT_CREATED", true);
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                "tenant", tenant,
                "owner", Map.of("id", savedOwner.getId(), "username", savedOwner.getUsername(), "role", "OWNER")));
    }

    @PatchMapping("/{tenantId}/suspend")
    @Transactional
    @PreAuthorize("hasAuthority('tenant:suspend')")
    public ResponseEntity<?> suspend(@PathVariable Long tenantId, Authentication authentication) {
        Tenant tenant = tenants.findById(tenantId).orElse(null);
        if (tenant == null) return ResponseEntity.notFound().build();
        tenant.setActive(false);
        tenants.save(tenant);
        for (User user : users.findAllByTenantId(tenantId)) {
            user.setPermissionVersion(user.getPermissionVersion() + 1);
            users.save(user);
            refreshTokens.findAllByUserIdAndRevokedAtIsNull(user.getId()).forEach(token -> {
                token.setRevokedAt(OffsetDateTime.now());
                refreshTokens.save(token);
            });
            devices.findAllByUserIdAndActiveTrue(user.getId()).forEach(device -> {
                device.setActive(false);
                devices.save(device);
            });
        }
        audit.record(null, authentication.getName(), "TENANT_SUSPENDED", true);
        return ResponseEntity.noContent().build();
    }

    @PatchMapping("/{tenantId}/activate")
    @Transactional
    @PreAuthorize("hasAuthority('tenant:activate')")
    public ResponseEntity<?> activate(@PathVariable Long tenantId, Authentication authentication) {
        Tenant tenant = tenants.findById(tenantId).orElse(null);
        if (tenant == null) return ResponseEntity.notFound().build();
        tenant.setActive(true);
        tenants.save(tenant);
        audit.record(null, authentication.getName(), "TENANT_ACTIVATED", true);
        return ResponseEntity.noContent().build();
    }
}
