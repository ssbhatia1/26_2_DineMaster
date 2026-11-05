package com.dinemaster.config;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserRepository;
import com.dinemaster.role.Roles;


import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

@Configuration
public class SecurityBeansConfig {
    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    UserDetailsService userDetailsService(UserRepository repository) {
        return username -> repository.findByUsername(username)
                .map(user -> org.springframework.security.core.userdetails.User
                        .withUsername(user.getUsername())
                        .password(user.getPassword())
                        .roles(Roles.canonical(user.getRole()))
                        .disabled(!user.isActive())
                        .build())
                .orElseThrow(
                        () -> new org.springframework.security.core.userdetails.UsernameNotFoundException(username));
    }
}