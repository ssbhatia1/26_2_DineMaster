package com.dinemaster.auth.controller;

import com.dinemaster.auth.dto.AuthResponse;
import com.dinemaster.auth.dto.LoginRequest;
import com.dinemaster.auth.dto.PasswordChangeRequest;
import com.dinemaster.auth.dto.RefreshRequest;
import com.dinemaster.auth.service.AuthService;
import com.dinemaster.auth.service.AuthSession;
import com.dinemaster.auth.service.LoginRateLimiter;
import com.dinemaster.auth.service.JwtService;
import com.dinemaster.common.exception.ApiErrorResponse;
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
import org.springframework.http.HttpStatus;
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
    private final JwtService jwtService;

    public AuthController(AuthService authService, UserRepository users, LoginRateLimiter loginRateLimiter,
            RolePermissionService rolePermissions, AuthDeviceRepository devices,
            RefreshTokenRepository refreshTokens, JwtService jwtService) {
        this.authService = authService;
        this.users = users;
        this.loginRateLimiter = loginRateLimiter;
        this.rolePermissions = rolePermissions;
        this.devices = devices;
        this.refreshTokens = refreshTokens;
        this.jwtService = jwtService;
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@Valid @RequestBody LoginRequest request, HttpServletRequest servletRequest) {
        if (!loginRateLimiter.allow(servletRequest.getRemoteAddr())) {
            return ApiErrorResponse.of(HttpStatus.TOO_MANY_REQUESTS, "RATE_LIMITED",
                    "Too many login attempts. Try again later.", null, servletRequest);
        }
        try {
            return ResponseEntity.ok(response(authService.login(
                    request.username(), request.password(), request.deviceLabel())));
        } catch (AuthService.AuthFailure failure) {
            boolean locked = failure.getStatus() == 423;
            return ApiErrorResponse.of(locked ? HttpStatus.LOCKED : HttpStatus.UNAUTHORIZED,
                    locked ? "ACCOUNT_LOCKED" : "INVALID_CREDENTIALS",
                    locked ? "Account temporarily locked." : "Invalid username or password.", null, servletRequest);
        }
    }

    @PostMapping("/refresh")
    public ResponseEntity<?> refresh(@Valid @RequestBody RefreshRequest request, HttpServletRequest servletRequest) {
        try {
            return ResponseEntity.ok(response(authService.refresh(request.refreshToken())));
        } catch (AuthService.AuthFailure failure) {
            return ApiErrorResponse.of(HttpStatus.valueOf(failure.getStatus()), "AUTH_TOKEN_INVALID",
                    "Refresh token is invalid or expired.", null, servletRequest);
        }
    }

    @PostMapping("/logout")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> logout(Authentication authentication, @Valid @RequestBody RefreshRequest request,
            HttpServletRequest servletRequest) {
        User user = currentUser(authentication);
        if (user == null) return ApiErrorResponse.of(HttpStatus.UNAUTHORIZED, "AUTH_TOKEN_INVALID",
                "Authentication is required.", null, servletRequest);
        authService.logout(user.getId(), request.refreshToken());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/logout-all")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> logoutAll(Authentication authentication, HttpServletRequest servletRequest) {
        User user = currentUser(authentication);
        if (user == null) return ApiErrorResponse.of(HttpStatus.UNAUTHORIZED, "AUTH_TOKEN_INVALID",
                "Authentication is required.", null, servletRequest);
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
    public ResponseEntity<?> permissions(Authentication authentication, HttpServletRequest servletRequest) {
        User user = currentUser(authentication);
        if (user == null) return ApiErrorResponse.of(HttpStatus.UNAUTHORIZED, "AUTH_TOKEN_INVALID",
                "Authentication is required.", null, servletRequest);
        return ResponseEntity.ok(Map.of(
                "permissions", rolePermissions.permissionsFor(user.getRole(), user.getTenantId()),
                "permVersion", user.getPermissionVersion()));
    }

    @GetMapping("/jwks")
    public ResponseEntity<?> jwks(HttpServletRequest servletRequest) {
        try {
            return ResponseEntity.ok(jwtService.jwks());
        } catch (IllegalStateException exception) {
            return ApiErrorResponse.of(HttpStatus.SERVICE_UNAVAILABLE, "JWKS_UNAVAILABLE",
                    "RSA signing keys are not configured.", null, servletRequest);
        }
    }

    @GetMapping("/devices")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> devices(Authentication authentication, HttpServletRequest servletRequest) {
        User user = currentUser(authentication);
        if (user == null) return ApiErrorResponse.of(HttpStatus.UNAUTHORIZED, "AUTH_TOKEN_INVALID",
                "Authentication is required.", null, servletRequest);
        return ResponseEntity.ok(devices.findAllByUserIdAndActiveTrue(user.getId()).stream()
                .map(device -> Map.of("deviceId", device.getId(), "label", device.getLabel(),
                        "createdAt", device.getCreatedAt(), "lastSeenAt", device.getLastSeenAt()))
                .toList());
    }

    @PostMapping("/devices/{deviceId}/revoke")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> revokeDevice(Authentication authentication, @PathVariable UUID deviceId,
            HttpServletRequest servletRequest) {
        User user = currentUser(authentication);
        if (user == null) return ApiErrorResponse.of(HttpStatus.UNAUTHORIZED, "AUTH_TOKEN_INVALID",
                "Authentication is required.", null, servletRequest);
        AuthDevice device = devices.findById(deviceId)
                .filter(value -> value.getUserId().equals(user.getId())).orElse(null);
        if (device == null) return ApiErrorResponse.of(HttpStatus.NOT_FOUND, "NOT_FOUND",
                "Device was not found.", null, servletRequest);
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
