package com.dinemaster.auth.service;

import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class LoginRateLimiter {
    private static final int LIMIT = 10;
    private static final long WINDOW_SECONDS = 60;
    private final Map<String, ArrayDeque<Long>> attempts = new ConcurrentHashMap<>();

    public synchronized boolean allow(String clientKey) {
        long now = Instant.now().getEpochSecond();
        ArrayDeque<Long> recent = attempts.computeIfAbsent(clientKey, ignored -> new ArrayDeque<>());
        while (!recent.isEmpty() && now - recent.peekFirst() >= WINDOW_SECONDS) recent.removeFirst();
        if (recent.size() >= LIMIT) return false;
        recent.addLast(now);
        if (attempts.size() > 5000) {
            attempts.entrySet().removeIf(entry -> entry.getValue().isEmpty()
                    || now - entry.getValue().peekLast() > WINDOW_SECONDS * 5);
        }
        return true;
    }
}
