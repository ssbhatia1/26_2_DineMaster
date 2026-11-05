package com.dinemaster.config;



import com.dinemaster.role.Roles;
import com.dinemaster.role.RolePermissionService;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserRepository;
import com.dinemaster.user.repository.UserRoleRepository;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

@Configuration
public class SecurityBeansConfig {
    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    UserDetailsService userDetailsService(UserRepository repository, RolePermissionService rolePermissions,
            UserRoleRepository userRoles) {
        return username -> repository.findByUsername(username)
                .map(user -> {
                    var authorities = new java.util.ArrayList<SimpleGrantedAuthority>();
                    String role = Roles.canonical(userRoles.findRoleCode(user.getId()).orElse(user.getRole()));
                    authorities.add(new SimpleGrantedAuthority("ROLE_" + role));
                    if (role.equals("OWNER")) authorities.add(new SimpleGrantedAuthority("ROLE_RESTAURANT_ADMIN"));
                    rolePermissions.permissionsFor(role, user.getTenantId())
                            .forEach(permission -> authorities.add(new SimpleGrantedAuthority(permission)));
                    return org.springframework.security.core.userdetails.User.withUsername(user.getUsername())
                            .password(user.getPassword()).authorities(authorities).disabled(!user.isActive()).build();
                })
                .orElseThrow(
                        () -> new org.springframework.security.core.userdetails.UsernameNotFoundException(username));
    }
}
