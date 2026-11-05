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
    private final String jwtPrivateKey;
    private final String jwtPublicKey;
    private final String datasourceUrl;
    private final String datasourcePassword;

    public AppStartupValidator(
            Environment environment,
            @Value("${app.jwt.secret:}") String jwtSecret,
            @Value("${app.jwt.private-key-pem:}") String jwtPrivateKey,
            @Value("${app.jwt.public-key-pem:}") String jwtPublicKey,
            @Value("${spring.datasource.url:}") String datasourceUrl,
            @Value("${spring.datasource.password:}") String datasourcePassword) {
        this.environment = environment;
        this.jwtSecret = jwtSecret;
        this.jwtPrivateKey = jwtPrivateKey;
        this.jwtPublicKey = jwtPublicKey;
        this.datasourceUrl = datasourceUrl;
        this.datasourcePassword = datasourcePassword;
    }

    @Override
    public void afterPropertiesSet() {
        if (Arrays.stream(environment.getActiveProfiles()).anyMatch("test"::equalsIgnoreCase)) {
            return;
        }

        int secretBytes = jwtSecret == null ? 0 : jwtSecret.getBytes(StandardCharsets.UTF_8).length;
        boolean hasKeyPair = jwtPrivateKey != null && !jwtPrivateKey.isBlank()
                && jwtPublicKey != null && !jwtPublicKey.isBlank();
        boolean partialKeyPair = (jwtPrivateKey != null && !jwtPrivateKey.isBlank())
                != (jwtPublicKey != null && !jwtPublicKey.isBlank());
        if (partialKeyPair) {
            throw new IllegalStateException("JWT_PRIVATE_KEY_PEM and JWT_PUBLIC_KEY_PEM must be configured together.");
        }
        if (Arrays.stream(environment.getActiveProfiles()).anyMatch("prod"::equalsIgnoreCase) && !hasKeyPair) {
            throw new IllegalStateException("Production requires an RS256 JWT key pair.");
        }
        if (!hasKeyPair && secretBytes < 32) {
            throw new IllegalStateException(
                    "Configure JWT_PRIVATE_KEY_PEM and JWT_PUBLIC_KEY_PEM, or a JWT_SECRET of at least 32 bytes, in a gitignored env file.");
        }

        if (datasourceUrl != null && datasourceUrl.contains("postgresql")
                && (datasourcePassword == null || datasourcePassword.isBlank())) {
            throw new IllegalStateException(
                    "DB_PASSWORD is required for PostgreSQL. Set it in %USERPROFILE%\\.dinemaster\\local.env or backend\\.env (gitignored), then restart the backend.");
        }
    }
}
