package com.dinemaster.auth.controller;

import com.dinemaster.auth.dto.AuthResponse;
import com.dinemaster.auth.dto.LoginRequest;
import com.dinemaster.auth.dto.SuperAdminLoginRequest;
import com.dinemaster.auth.dto.PasswordChangeRequest;
import com.dinemaster.auth.dto.RefreshRequest;
import com.dinemaster.auth.dto.DeviceActivationRequest;
import com.dinemaster.auth.dto.ActivationCodeCreateRequest;
import com.dinemaster.auth.entity.DeviceActivation;
import com.dinemaster.auth.repository.DeviceActivationRepository;
import com.dinemaster.restaurant.repository.RestaurantRepository;
import com.dinemaster.auth.service.AuthService;
import com.dinemaster.auth.service.AuthSession;
import com.dinemaster.auth.service.JwtService;
import com.dinemaster.auth.service.LoginRateLimiter;
import com.dinemaster.user.dto.UserResponse;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserRepository;
import com.dinemaster.user.repository.UserBranchRepository;
import com.dinemaster.role.RolePermissionService;
import com.dinemaster.tenant.TenantRepository;
import com.dinemaster.auth.entity.AuthDevice;
import com.dinemaster.auth.repository.AuthDeviceRepository;
import com.dinemaster.auth.repository.RefreshTokenRepository;
import com.dinemaster.common.exception.ApiErrorResponse;
import java.time.OffsetDateTime;
import java.util.UUID;
import java.security.SecureRandom;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.HexFormat;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;
import org.springframework.transaction.annotation.Transactional;
import jakarta.servlet.http.HttpServletRequest;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
    private final AuthService authService;
    private final UserRepository users;
    private final LoginRateLimiter loginRateLimiter;
    private final RolePermissionService rolePermissions;
    private final AuthDeviceRepository devices;
    private final RefreshTokenRepository refreshTokens;
    private final UserBranchRepository userBranches;
    private final JwtService jwtService;
    private final DeviceActivationRepository activations;
    private final RestaurantRepository branches;
    private final TenantRepository tenants;
    private final java.security.SecureRandom secureRandom = new SecureRandom();

    public AuthController(AuthService authService, UserRepository users, LoginRateLimiter loginRateLimiter,
            RolePermissionService rolePermissions, AuthDeviceRepository devices,
            RefreshTokenRepository refreshTokens, UserBranchRepository userBranches, JwtService jwtService,
            DeviceActivationRepository activations, RestaurantRepository branches, TenantRepository tenants) {
        this.authService = authService;
        this.users = users;
        this.loginRateLimiter = loginRateLimiter;
        this.rolePermissions = rolePermissions;
        this.devices = devices;
        this.refreshTokens = refreshTokens;
        this.userBranches = userBranches;
        this.jwtService = jwtService;
        this.activations = activations;
        this.branches = branches;
        this.tenants = tenants;
    }

    @PostMapping("/devices/activation-codes")
    @PreAuthorize("hasAuthority('device:activate')")
    public ResponseEntity<?> createActivationCode(Authentication authentication,
            @Valid @RequestBody ActivationCodeCreateRequest request) {
        User actor = currentUser(authentication);
        var branch = branches.findById(request.branchId()).orElse(null);
        if (actor == null || branch == null || !java.util.Objects.equals(actor.getTenantId(), branch.getTenantId())
                || tenants.findById(branch.getTenantId()).filter(com.dinemaster.tenant.Tenant::isActive).isEmpty())
            return ResponseEntity.notFound().build();
        byte[] bytes = new byte[24]; secureRandom.nextBytes(bytes);
        String code = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        activations.save(new DeviceActivation(UUID.randomUUID(), actor.getTenantId(), branch.getId(),
                sha256(code), OffsetDateTime.now().plusMinutes(15)));
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("activationCode", code,
                "expiresAt", OffsetDateTime.now().plusMinutes(15)));
    }

    @PostMapping("/devices/activate")
    @Transactional
    public ResponseEntity<?> activateDevice(@Valid @RequestBody DeviceActivationRequest request,
            HttpServletRequest servletRequest) {
        if (!loginRateLimiter.allow(servletRequest.getRemoteAddr()))
            return ResponseEntity.status(429).body(Map.of("error", "Too many activation attempts", "code", "RATE_LIMITED"));
        DeviceActivation activation = activations.findByCodeHashForUpdate(sha256(request.activationCode()))
                .orElse(null);
        OffsetDateTime now = OffsetDateTime.now();
        if (activation == null || activation.getConsumedAt() != null || !activation.getExpiresAt().isAfter(now))
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Invalid activation code"));
        if (tenants.findById(activation.getTenantId()).filter(com.dinemaster.tenant.Tenant::isActive).isEmpty())
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("error", "Tenant is suspended"));
        String deviceLabel = request.deviceName().trim();
        if (deviceLabel.length() > 100) deviceLabel = deviceLabel.substring(0, 100);
        AuthDevice device = new AuthDevice(UUID.randomUUID(), null, activation.getTenantId(), deviceLabel);
        device.setPlatform(request.platform().trim());
        device.setBranchId(activation.getBranchId());
        devices.save(device);
        activation.setConsumedAt(now);
        activations.save(activation);
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("deviceId", device.getId(),
                "tenantId", device.getTenantId(), "branchId", activation.getBranchId()));
    }

    private String sha256(String value) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(value.getBytes(StandardCharsets.UTF_8))); }
        catch (Exception exception) { throw new IllegalStateException("SHA-256 unavailable", exception); }
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@Valid @RequestBody LoginRequest request, HttpServletRequest servletRequest) {
        if (!loginRateLimiter.allow(servletRequest.getRemoteAddr())) {
            return ResponseEntity.status(429).body(Map.of("error", "Too many login attempts", "code", "RATE_LIMITED"));
        }
        try {
            return ResponseEntity.ok(response(authService.login(
                    request.tenantCode(), request.username(), request.password(), request.deviceId())));
        } catch (AuthService.AuthFailure failure) {
            return ResponseEntity.status(failure.getStatus()).body(Map.of(
                    "error", failure.getMessage(),
                    "code", failure.getStatus() == 423 ? "ACCOUNT_LOCKED" : "INVALID_CREDENTIALS"));
        }
    }

    @PostMapping("/super-admin/login")
    public ResponseEntity<?> superAdminLogin(@Valid @RequestBody SuperAdminLoginRequest request,
            HttpServletRequest servletRequest) {
        if (!loginRateLimiter.allow(servletRequest.getRemoteAddr())) {
            return ResponseEntity.status(429).body(Map.of("error", "Too many login attempts", "code", "RATE_LIMITED"));
        }
        try {
            return ResponseEntity.ok(response(authService.loginSuperAdmin(request.username(), request.password())));
        } catch (AuthService.AuthFailure failure) {
            return ResponseEntity.status(failure.getStatus()).body(Map.of(
                    "error", failure.getMessage(),
                    "code", failure.getStatus() == 423 ? "ACCOUNT_LOCKED" : "INVALID_CREDENTIALS"));
        }
    }

    @GetMapping("/jwks")
    public ResponseEntity<?> jwks() {
        try {
            return ResponseEntity.ok(jwtService.jwks());
        } catch (IllegalStateException exception) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(Map.of("error", "RSA signing keys are not configured"));
        }
    }

    @PostMapping("/refresh")
    public ResponseEntity<?> refresh(@Valid @RequestBody RefreshRequest request) {
        try {
            return ResponseEntity.ok(response(authService.refresh(request.refreshToken())));
        } catch (AuthService.AuthFailure failure) {
            return ResponseEntity.status(failure.getStatus()).body(Map.of(
                    "error", failure.getMessage(), "code", "AUTH_TOKEN_INVALID"));
        }
    }

    @PostMapping("/logout")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> logout(Authentication authentication, @Valid @RequestBody RefreshRequest request) {
        User user = currentUser(authentication);
        if (user == null) return ResponseEntity.status(401).body(Map.of("error", "Unauthorized"));
        authService.logout(user.getId(), request.refreshToken());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/logout-all")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> logoutAll(Authentication authentication) {
        User user = currentUser(authentication);
        if (user == null) return ResponseEntity.status(401).body(Map.of("error", "Unauthorized"));
        authService.logoutAll(user.getId());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/me")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> me(Authentication authentication, HttpServletRequest servletRequest) {
        User user = currentUser(authentication);
        if (user == null) return ApiErrorResponse.of(HttpStatus.UNAUTHORIZED, "AUTH_TOKEN_INVALID",
                "Authentication is required.", null, servletRequest);
        return ResponseEntity.ok(UserResponse.from(user, rolePermissions.permissionsFor(user.getRole(), user.getTenantId())));
    }

    @PostMapping({"/change-password", "/password/change"})
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> changePassword(Authentication authentication,
            @Valid @RequestBody PasswordChangeRequest request, HttpServletRequest servletRequest) {
        User user = currentUser(authentication);
        if (user == null) return ApiErrorResponse.of(HttpStatus.UNAUTHORIZED, "AUTH_TOKEN_INVALID",
                "Authentication is required.", null, servletRequest);
        try {
            authService.changePassword(user.getId(), request.currentPassword(), request.newPassword());
            return ResponseEntity.noContent().build();
        } catch (AuthService.AuthFailure failure) {
            return ApiErrorResponse.of(HttpStatus.valueOf(failure.getStatus()),
                    failure.getStatus() == 401 ? "CURRENT_PASSWORD_INVALID" : "VALIDATION_FAILED",
                    failure.getStatus() == 401 ? "Current password is incorrect." : failure.getMessage(),
                    null, servletRequest);
        }
    }

    @GetMapping("/me/permissions")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> permissions(Authentication authentication) {
        User user = currentUser(authentication);
        if (user == null) return ResponseEntity.status(401).body(Map.of("error", "Unauthorized"));
        return ResponseEntity.ok(Map.of(
                "userId", user.getId(),
                "permVersion", user.getPermissionVersion(),
                "permissions", rolePermissions.permissionsFor(user.getRole(), user.getTenantId())));
    }

    @GetMapping("/devices")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> devices(Authentication authentication) {
        User user = currentUser(authentication);
        if (user == null) return ResponseEntity.status(401).body(Map.of("error", "Unauthorized"));
        return ResponseEntity.ok(devices.findAllByUserIdAndActiveTrue(user.getId()).stream()
                .map(device -> Map.of("deviceId", device.getId(), "label", device.getLabel(),
                        "createdAt", device.getCreatedAt(), "lastSeenAt", device.getLastSeenAt()))
                .toList());
    }

    @PostMapping("/devices/{deviceId}/revoke")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> revokeDevice(Authentication authentication, @PathVariable UUID deviceId) {
        User user = currentUser(authentication);
        if (user == null) return ResponseEntity.status(401).body(Map.of("error", "Unauthorized"));
        AuthDevice device = devices.findById(deviceId)
                .filter(value -> value.getUserId().equals(user.getId())).orElse(null);
        if (device == null) return ResponseEntity.notFound().build();
        device.setActive(false);
        devices.save(device);
        refreshTokens.findAllByDeviceIdAndRevokedAtIsNull(deviceId).forEach(token -> {
            token.setRevokedAt(OffsetDateTime.now());
            refreshTokens.save(token);
        });
        return ResponseEntity.noContent().build();
    }

    private AuthResponse response(AuthSession session) {
        return new AuthResponse(session.accessToken(), session.accessToken(), session.refreshToken(), "Bearer",
                session.expiresIn(), session.user(), session.tenantId(), session.branchIds(),
                session.deviceId(), session.permVersion());
    }

    private User currentUser(Authentication authentication) {
        if (authentication == null || !(authentication.getPrincipal() instanceof UserDetails details)) return null;
        return users.findByUsername(details.getUsername()).filter(User::isActive).orElse(null);
    }
}
