package com.dinemaster.config;



import com.dinemaster.auth.service.JwtService;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserRepository;
import com.dinemaster.user.repository.UserBranchRepository;
import com.dinemaster.auth.repository.AuthDeviceRepository;
import com.dinemaster.tenant.TenantRepository;
import com.dinemaster.user.repository.UserRoleRepository;
import io.jsonwebtoken.Claims;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;
import java.util.List;
import java.util.UUID;

@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {
    private final JwtService jwtService;
    private final UserDetailsService userDetailsService;
    private final UserRepository users;
    private final UserBranchRepository branches;
    private final AuthDeviceRepository devices;
    private final TenantRepository tenants;
    private final UserRoleRepository userRoles;

    public JwtAuthenticationFilter(JwtService jwtService, UserDetailsService userDetailsService,
            UserRepository users, UserBranchRepository branches, AuthDeviceRepository devices,
            TenantRepository tenants, UserRoleRepository userRoles) {
        this.jwtService = jwtService;
        this.userDetailsService = userDetailsService;
        this.users = users;
        this.branches = branches;
        this.devices = devices;
        this.tenants = tenants;
        this.userRoles = userRoles;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return "OPTIONS".equalsIgnoreCase(request.getMethod());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")
                && SecurityContextHolder.getContext().getAuthentication() == null) {
            try {
                String rawToken = header.substring(7);
                Claims claims = jwtService.claims(rawToken);
                String username = claims.getSubject();
                var user = userDetailsService.loadUserByUsername(username);
                User account = users.findByUsername(username).orElse(null);
                boolean passwordChangeRequest = request.getRequestURI().equals("/api/v1/auth/change-password")
                        || request.getRequestURI().equals("/api/v1/auth/password/change");
                if (user.isEnabled() && account != null && tokenMatchesCurrentScope(claims, account)
                        && (!account.isMustChangePassword() || passwordChangeRequest)) {
                    var authentication = new UsernamePasswordAuthenticationToken(user, null, user.getAuthorities());
                    authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                    SecurityContextHolder.getContext().setAuthentication(authentication);
                }
            } catch (RuntimeException ignored) {
                // Invalid tokens remain unauthenticated and are rejected by authorization
                // rules.
            }
        }
        filterChain.doFilter(request, response);
    }

    private boolean tokenMatchesCurrentScope(Claims claims, User user) {
        String assignedRole = com.dinemaster.role.Roles.canonical(
                userRoles.findRoleCode(user.getId()).orElse(user.getRole()));
        Object rawUserId = claims.get("userId");
        Object rawTenantId = claims.get("tenantId");
        Object rawPermissionVersion = claims.get("permVersion");
        Number tokenUserId = rawUserId instanceof Number number ? number : null;
        Number tokenTenantId = rawTenantId instanceof Number number ? number : null;
        Number tokenPermissionVersion = rawPermissionVersion instanceof Number number ? number : null;
        if (tokenUserId == null || tokenUserId.longValue() != user.getId()
                || tokenPermissionVersion == null || tokenPermissionVersion.intValue() != user.getPermissionVersion()
                || !assignedRole.equals(
                        com.dinemaster.role.Roles.canonical(claims.get("role", String.class)))) {
            return false;
        }
        if (!java.util.Objects.equals(tokenTenantId == null ? null : tokenTenantId.longValue(), user.getTenantId())) {
            return false;
        }
        if (user.getTenantId() == null) {
            if (!assignedRole.equals("SUPER_ADMIN") || tokenTenantId != null) return false;
        } else if (tenants.findById(user.getTenantId())
                .filter(com.dinemaster.tenant.Tenant::isActive).isEmpty()) return false;
        Object rawBranches = claims.get("branchIds");
        if (!(rawBranches instanceof List<?> claimList)) return false;
        List<Long> tokenBranches = claimList.stream()
                .filter(Number.class::isInstance).map(Number.class::cast).map(Number::longValue).sorted().toList();
        if (tokenBranches.size() != claimList.size() || !tokenBranches.equals(branches.findBranchIds(user.getId()))) {
            return false;
        }
        String rawDeviceId = claims.get("deviceId", String.class);
        if (rawDeviceId == null) {
            return true;
        }
        UUID deviceId = UUID.fromString(rawDeviceId);
        return devices.findById(deviceId)
                .filter(device -> device.isActive() && device.getUserId().equals(user.getId())
                        && java.util.Objects.equals(device.getTenantId(), user.getTenantId()))
                .isPresent();
    }
}
