package com.dinemaster.auth.controller;

import com.dinemaster.auth.dto.AuthResponse;
import com.dinemaster.auth.dto.LoginRequest;
import com.dinemaster.auth.dto.PasswordChangeRequest;
import com.dinemaster.auth.dto.RefreshRequest;
import com.dinemaster.auth.service.AuthService;
import com.dinemaster.auth.service.AuthSession;
import com.dinemaster.auth.service.LoginRateLimiter;
import com.dinemaster.user.dto.UserResponse;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserRepository;
import com.dinemaster.role.RolePermissionService;
import com.dinemaster.auth.entity.AuthDevice;
import com.dinemaster.auth.repository.AuthDeviceRepository;
import com.dinemaster.auth.repository.RefreshTokenRepository;
import java.time.OffsetDateTime;
import java.util.UUID;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;
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

    public AuthController(AuthService authService, UserRepository users, LoginRateLimiter loginRateLimiter,
            RolePermissionService rolePermissions, AuthDeviceRepository devices,
            RefreshTokenRepository refreshTokens) {
        this.authService = authService;
        this.users = users;
        this.loginRateLimiter = loginRateLimiter;
        this.rolePermissions = rolePermissions;
        this.devices = devices;
        this.refreshTokens = refreshTokens;
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@Valid @RequestBody LoginRequest request, HttpServletRequest servletRequest) {
        if (!loginRateLimiter.allow(servletRequest.getRemoteAddr())) {
            return ResponseEntity.status(429).body(Map.of("error", "Too many login attempts", "code", "RATE_LIMITED"));
        }
        try {
            return ResponseEntity.ok(response(authService.login(
                    request.username(), request.password(), request.deviceLabel())));
        } catch (AuthService.AuthFailure failure) {
            return ResponseEntity.status(failure.getStatus()).body(Map.of(
                    "error", failure.getMessage(),
                    "code", failure.getStatus() == 423 ? "ACCOUNT_LOCKED" : "INVALID_CREDENTIALS"));
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

    @GetMapping("/me")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> me(Authentication authentication) {
        User user = currentUser(authentication);
        if (user == null) return ResponseEntity.status(401).body(Map.of("error", "Unauthorized"));
        return ResponseEntity.ok(UserResponse.from(user, rolePermissions.permissionsFor(user.getRole(), user.getTenantId())));
    }

    @PostMapping("/password/change")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> changePassword(Authentication authentication,
            @Valid @RequestBody PasswordChangeRequest request) {
        User user = currentUser(authentication);
        if (user == null) return ResponseEntity.status(401).body(Map.of("error", "Unauthorized"));
        try {
            authService.changePassword(user.getId(), request.currentPassword(), request.newPassword());
            return ResponseEntity.noContent().build();
        } catch (AuthService.AuthFailure failure) {
            return ResponseEntity.status(failure.getStatus()).body(Map.of("error", failure.getMessage()));
        }
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
