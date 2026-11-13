package com.dinemaster.config;




import com.dinemaster.user.entity.User;
import com.dinemaster.common.exception.ApiErrorResponse;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.beans.factory.annotation.Value;

import java.util.List;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtFilter;
    private final ObjectMapper objectMapper;
    @Value("${dinemaster.guest.allowed-origin:}")
    private String guestAllowedOrigin;

    public SecurityConfig(JwtAuthenticationFilter jwtFilter, ObjectMapper objectMapper) {
        this.jwtFilter = jwtFilter;
        this.objectMapper = objectMapper;
    }

    @Bean
    CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOriginPatterns(List.of(
                "http://localhost:*",
                "http://127.0.0.1:*"));
        if (guestAllowedOrigin != null && !guestAllowedOrigin.isBlank()) {
            configuration.addAllowedOrigin(guestAllowedOrigin.trim());
        }
        configuration.setAllowedMethods(List.of(
                "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        configuration.setAllowedHeaders(List.of("*"));
        configuration.setExposedHeaders(List.of("Authorization"));
        configuration.setAllowCredentials(false);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .cors(Customizer.withDefaults())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(handling -> handling
                        .authenticationEntryPoint((request, response, exception) -> {
                            writeSecurityError(response, HttpStatus.UNAUTHORIZED, "AUTH_TOKEN_INVALID",
                                    "Authentication is required.", request);
                        })
                        .accessDeniedHandler((request, response, exception) -> {
                            writeSecurityError(response, HttpStatus.FORBIDDEN, "PERMISSION_DENIED",
                                    "You do not have permission to access this resource.", request);
                        }))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        .requestMatchers("/", "/api/v1/health", "/error", "/api/v1/auth/**").permitAll()
                        // Protected controller methods enforce authorization with @PreAuthorize.
                        // Let unmatched paths reach MVC so invalid URLs return 404, not 401.
                        .anyRequest().permitAll())
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable());

        http.addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }

    private void writeSecurityError(jakarta.servlet.http.HttpServletResponse response,
            HttpStatus status, String code, String message, jakarta.servlet.http.HttpServletRequest request)
            throws java.io.IOException {
        var entity = ApiErrorResponse.of(status, code, message, null, request);
        response.setStatus(status.value());
        response.setContentType("application/json");
        response.setCharacterEncoding(java.nio.charset.StandardCharsets.UTF_8.name());
        response.setHeader("X-Request-Id", entity.getHeaders().getFirst("X-Request-Id"));
        objectMapper.writeValue(response.getWriter(), entity.getBody());
    }
}
