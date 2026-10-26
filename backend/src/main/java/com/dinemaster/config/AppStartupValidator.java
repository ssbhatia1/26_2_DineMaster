package com.dinemaster.config;

import org.springframework.beans.factory.InitializingBean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;

@Component
public class AppStartupValidator implements InitializingBean {

    private final Environment environment;
    private final String jwtSecret;
    private final String datasourceUrl;
    private final String datasourcePassword;

    public AppStartupValidator(
            Environment environment,
            @Value("${app.jwt.secret:}") String jwtSecret,
            @Value("${spring.datasource.url:}") String datasourceUrl,
            @Value("${spring.datasource.password:}") String datasourcePassword) {
        this.environment = environment;
        this.jwtSecret = jwtSecret;
        this.datasourceUrl = datasourceUrl;
        this.datasourcePassword = datasourcePassword;
    }

    @Override
    public void afterPropertiesSet() {
        if (Arrays.stream(environment.getActiveProfiles()).anyMatch("test"::equalsIgnoreCase)) {
            return;
        }

        int secretBytes = jwtSecret == null ? 0 : jwtSecret.getBytes(StandardCharsets.UTF_8).length;
        if (secretBytes < 32) {
            throw new IllegalStateException(
                    "JWT_SECRET must be at least 32 bytes. Set it in %USERPROFILE%\\.dinemaster\\local.env or backend\\.env (gitignored), then restart the backend.");
        }

        if (datasourceUrl != null && datasourceUrl.contains("postgresql")
                && (datasourcePassword == null || datasourcePassword.isBlank())) {
            throw new IllegalStateException(
                    "DB_PASSWORD is required for PostgreSQL. Set it in %USERPROFILE%\\.dinemaster\\local.env or backend\\.env (gitignored), then restart the backend.");
        }
    }
}
