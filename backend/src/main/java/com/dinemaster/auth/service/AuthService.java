package com.dinemaster.auth.service;

import com.dinemaster.auth.entity.RefreshToken;
import com.dinemaster.auth.entity.AuthDevice;
import com.dinemaster.auth.repository.AuthDeviceRepository;
import com.dinemaster.auth.repository.RefreshTokenRepository;
import com.dinemaster.user.dto.UserResponse;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserRepository;
import com.dinemaster.user.repository.UserBranchRepository;
import com.dinemaster.role.RolePermissionService;
import com.dinemaster.tenant.TenantRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;

@Service
public class AuthService {
    private static final int MAX_FAILURES = 5;
    private static final long LOCK_MINUTES = 15;
    private static final long REFRESH_DAYS = 7;

    private final UserRepository users;
    private final RefreshTokenRepository refreshTokens;
    private final AuthDeviceRepository devices;
    private final UserBranchRepository userBranches;
    private final RolePermissionService rolePermissions;
    private final TenantRepository tenants;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final AuthAuditService audit;
    private final long accessLifetimeMs;
    private final SecureRandom random = new SecureRandom();

    public AuthService(UserRepository users, RefreshTokenRepository refreshTokens,
            AuthDeviceRepository devices, UserBranchRepository userBranches,
            RolePermissionService rolePermissions, TenantRepository tenants,
            PasswordEncoder passwordEncoder, JwtService jwtService, AuthAuditService audit,
            @Value("${app.jwt.expiration-ms:900000}") long accessLifetimeMs) {
        this.users = users;
        this.refreshTokens = refreshTokens;
        this.devices = devices;
        this.userBranches = userBranches;
        this.rolePermissions = rolePermissions;
        this.tenants = tenants;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.audit = audit;
        this.accessLifetimeMs = accessLifetimeMs;
    }

    @Transactional(noRollbackFor = AuthFailure.class)
    public AuthSession login(String rawUsername, String password, String deviceLabel) {
        String username = rawUsername == null ? "" : rawUsername.trim();
        User user = users.findForAuthenticationByUsername(username).orElse(null);
        if (user == null || !user.isActive()) {
            audit.record(user == null ? null : user.getId(), username, "LOGIN", false);
            throw new AuthFailure(401, "Invalid username or password");
        }
        if (!isPlatformAdmin(user) && (user.getTenantId() == null || tenants.findById(user.getTenantId())
                .filter(com.dinemaster.tenant.Tenant::isActive).isEmpty())) {
            audit.record(user.getId(), username, "LOGIN_TENANT_SUSPENDED", false);
            throw new AuthFailure(403, "Tenant is suspended");
        }

        OffsetDateTime now = OffsetDateTime.now();
        if (user.getLockedUntil() != null && user.getLockedUntil().isAfter(now)) {
            audit.record(user.getId(), username, "LOGIN_LOCKED", false);
            throw new AuthFailure(423, "Account temporarily locked");
        }
        if (user.getLockedUntil() != null) {
            user.setLockedUntil(null);
            user.setFailedLoginAttempts((short) 0);
        }

        if (password == null || !passwordEncoder.matches(password, user.getPassword())) {
            short failures = (short) (user.getFailedLoginAttempts() + 1);
            user.setFailedLoginAttempts(failures);
            if (failures >= MAX_FAILURES) {
                user.setLockedUntil(now.plusMinutes(LOCK_MINUTES));
                user.setFailedLoginAttempts((short) 0);
            }
            users.save(user);
            audit.record(user.getId(), username, "LOGIN", false);
            if (user.getLockedUntil() != null && user.getLockedUntil().isAfter(now)) {
                throw new AuthFailure(423, "Account temporarily locked");
            }
            throw new AuthFailure(401, "Invalid username or password");
        }

        user.setFailedLoginAttempts((short) 0);
        user.setLockedUntil(null);
        users.save(user);
        audit.record(user.getId(), username, "LOGIN", true);
        UUID deviceId = registerDevice(user, deviceLabel);
        String rawRefresh = issueRefreshToken(user.getId(), UUID.randomUUID(), deviceId);
        return session(user, rawRefresh, deviceId);
    }

    @Transactional(noRollbackFor = AuthFailure.class)
    public AuthSession refresh(String rawToken) {
        RefreshToken current = refreshTokens.findByTokenHashForUpdate(hash(rawToken))
                .orElseThrow(() -> new AuthFailure(401, "Invalid refresh token"));
        if (current.getRevokedAt() != null) {
            refreshTokens.findAllByFamilyIdAndRevokedAtIsNull(current.getFamilyId()).forEach(token -> {
                token.setRevokedAt(OffsetDateTime.now());
                refreshTokens.save(token);
            });
            audit.record(current.getUserId(), "user:" + current.getUserId(), "REFRESH_REUSE", false);
            throw new AuthFailure(401, "Refresh token reuse detected; sign in again");
        }
        if (!current.getExpiresAt().isAfter(OffsetDateTime.now())) {
            current.setRevokedAt(OffsetDateTime.now());
            refreshTokens.save(current);
            throw new AuthFailure(401, "Refresh token expired");
        }
        User user = users.findById(current.getUserId()).filter(User::isActive).orElse(null);
        if (user == null) {
            refreshTokens.findAllByFamilyIdAndRevokedAtIsNull(current.getFamilyId()).forEach(token -> {
                token.setRevokedAt(OffsetDateTime.now());
                refreshTokens.save(token);
            });
            throw new AuthFailure(401, "Account unavailable");
        }
        if (!isPlatformAdmin(user) && (user.getTenantId() == null || tenants.findById(user.getTenantId())
                .filter(com.dinemaster.tenant.Tenant::isActive).isEmpty())) {
            refreshTokens.findAllByFamilyIdAndRevokedAtIsNull(current.getFamilyId()).forEach(token -> {
                token.setRevokedAt(OffsetDateTime.now());
                refreshTokens.save(token);
            });
            throw new AuthFailure(403, "Tenant is suspended");
        }
        UUID deviceId = current.getDeviceId();
        AuthDevice device = deviceId == null ? null : devices.findById(deviceId).orElse(null);
        if (device == null) {
            deviceId = registerDevice(user, null);
            current.setDeviceId(deviceId);
        } else if (!device.isActive() || !device.getUserId().equals(user.getId())) {
            refreshTokens.findAllByFamilyIdAndRevokedAtIsNull(current.getFamilyId()).forEach(token -> {
                token.setRevokedAt(OffsetDateTime.now());
                refreshTokens.save(token);
            });
            throw new AuthFailure(401, "Device session is no longer active");
        } else {
            device.setLastSeenAt(OffsetDateTime.now());
            devices.save(device);
        }
        String replacement = issueRefreshToken(user.getId(), current.getFamilyId(), deviceId);
        RefreshToken next = refreshTokens.findByTokenHash(hash(replacement)).orElseThrow();
        current.setRevokedAt(OffsetDateTime.now());
        current.setReplacedBy(next.getId());
        refreshTokens.save(current);
        audit.record(user.getId(), user.getUsername(), "TOKEN_REFRESH", true);
        return session(user, replacement, deviceId);
    }

    @Transactional
    public void logout(Long userId, String rawToken) {
        refreshTokens.findByTokenHash(hash(rawToken)).ifPresent(token -> {
            if (token.getUserId().equals(userId) && token.getRevokedAt() == null) {
                token.setRevokedAt(OffsetDateTime.now());
                refreshTokens.save(token);
            }
        });
        users.findById(userId).ifPresent(user -> audit.record(userId, user.getUsername(), "LOGOUT", true));
    }

    @Transactional
    public void logoutAll(Long userId) {
        OffsetDateTime now = OffsetDateTime.now();
        refreshTokens.findAllByUserIdAndRevokedAtIsNull(userId).forEach(token -> {
            token.setRevokedAt(now);
            refreshTokens.save(token);
        });
        users.findById(userId).ifPresent(user -> {
            user.setPermissionVersion(user.getPermissionVersion() + 1);
            users.save(user);
            audit.record(userId, user.getUsername(), "LOGOUT_ALL", true);
        });
    }

    @Transactional(noRollbackFor = AuthFailure.class)
    public void changePassword(Long userId, String currentPassword, String newPassword) {
        User user = users.findById(userId).filter(User::isActive)
                .orElseThrow(() -> new AuthFailure(404, "User not found"));
        if (!passwordEncoder.matches(currentPassword, user.getPassword())) {
            audit.record(userId, user.getUsername(), "PASSWORD_CHANGE", false);
            throw new AuthFailure(401, "Current password is incorrect");
        }
        if (newPassword == null || newPassword.length() < 10 || newPassword.length() > 128) {
            throw new AuthFailure(422, "New password must be between 10 and 128 characters");
        }
        user.setPassword(passwordEncoder.encode(newPassword));
        user.setPermissionVersion(user.getPermissionVersion() + 1);
        users.save(user);
        refreshTokens.findAllByUserIdAndRevokedAtIsNull(userId).forEach(token -> {
            token.setRevokedAt(OffsetDateTime.now());
            refreshTokens.save(token);
        });
        audit.record(userId, user.getUsername(), "PASSWORD_CHANGE", true);
    }

    private String issueRefreshToken(Long userId, UUID familyId, UUID deviceId) {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        String raw = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        RefreshToken token = new RefreshToken();
        token.setId(UUID.randomUUID());
        token.setFamilyId(familyId);
        token.setUserId(userId);
        token.setDeviceId(deviceId);
        token.setTokenHash(hash(raw));
        token.setExpiresAt(OffsetDateTime.now().plusDays(REFRESH_DAYS));
        token.setCreatedAt(OffsetDateTime.now());
        refreshTokens.save(token);
        return raw;
    }

    private UUID registerDevice(User user, String label) {
        UUID deviceId = UUID.randomUUID();
        devices.save(new AuthDevice(deviceId, user.getId(), user.getTenantId(), label));
        return deviceId;
    }

    private boolean isPlatformAdmin(User user) {
        return com.dinemaster.role.Roles.matches(user.getRole(), "SUPER_ADMIN") && user.getTenantId() == null;
    }

    private AuthSession session(User user, String rawRefresh, UUID deviceId) {
        var branches = userBranches.findBranchIds(user.getId());
        return new AuthSession(jwtService.createToken(user, deviceId, branches), rawRefresh,
                accessLifetimeMs / 1000, UserResponse.from(user, rolePermissions.permissionsFor(user.getRole(), user.getTenantId())), user.getTenantId(), branches,
                deviceId, user.getPermissionVersion());
    }

    private String hash(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest((value == null ? "" : value).getBytes(StandardCharsets.UTF_8)));
        } catch (Exception exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    public static final class AuthFailure extends RuntimeException {
        private final int status;
        public AuthFailure(int status, String message) { super(message); this.status = status; }
        public int getStatus() { return status; }
    }
}
