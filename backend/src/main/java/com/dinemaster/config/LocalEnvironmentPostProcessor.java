package com.dinemaster.config;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Loads gitignored local env files so JWT and database settings survive new terminals.
 * Existing OS environment variables always win over file values.
 */
public class LocalEnvironmentPostProcessor implements EnvironmentPostProcessor {

    @Override
    public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
        if (hasProfile(environment, "test")) {
            return;
        }

        Map<String, Object> values = new LinkedHashMap<>();
        loadFile(values, Path.of(System.getProperty("user.home"), ".dinemaster", "local.env"));
        loadFile(values, Path.of(".env"));
        loadFile(values, Path.of("backend", ".env"));

        if (!values.isEmpty()) {
            environment.getPropertySources().addLast(new MapPropertySource("dinemasterLocalEnv", values));
        }
    }

    private boolean hasProfile(ConfigurableEnvironment environment, String profile) {
        for (String active : environment.getActiveProfiles()) {
            if (profile.equalsIgnoreCase(active)) {
                return true;
            }
        }
        String configured = environment.getProperty("spring.profiles.active", "");
        return configured.toLowerCase().contains(profile);
    }

    private void loadFile(Map<String, Object> values, Path path) {
        if (path == null || !Files.isRegularFile(path)) {
            return;
        }
        try {
            for (String line : Files.readAllLines(path, StandardCharsets.UTF_8)) {
                String trimmed = line.trim();
                if (trimmed.isEmpty() || trimmed.startsWith("#")) {
                    continue;
                }
                if (trimmed.startsWith("export ")) {
                    trimmed = trimmed.substring(7).trim();
                }
                int separator = trimmed.indexOf('=');
                if (separator <= 0) {
                    continue;
                }
                String key = trimmed.substring(0, separator).trim();
                String value = unquote(trimmed.substring(separator + 1).trim());
                if (!key.isEmpty() && !values.containsKey(key) && System.getenv(key) == null) {
                    values.put(key, value);
                }
            }
        } catch (IOException ignored) {
            // Missing or unreadable local files should not crash configuration discovery.
        }
    }

    private String unquote(String value) {
        if (value.length() >= 2) {
            char first = value.charAt(0);
            char last = value.charAt(value.length() - 1);
            if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
                return value.substring(1, value.length() - 1);
            }
        }
        return value;
    }
}
