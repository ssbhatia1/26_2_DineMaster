package com.dinemaster.qr.service;

import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

@Component
public class GuestRateLimiter {
    private static final int LIMIT = 30;
    private static final long WINDOW_SECONDS = 60;
    private final Map<String, ArrayDeque<Long>> attempts = new ConcurrentHashMap<>();

    public synchronized boolean allow(String ip) {
        long now = Instant.now().getEpochSecond();
        ArrayDeque<Long> recent = attempts.computeIfAbsent(ip, ignored -> new ArrayDeque<>());
        while (!recent.isEmpty() && now - recent.peekFirst() >= WINDOW_SECONDS) recent.removeFirst();
        if (recent.size() >= LIMIT) return false;
        recent.addLast(now);
        if (attempts.size() > 5000) attempts.entrySet().removeIf(e -> e.getValue().isEmpty()
                || now - e.getValue().peekLast() > WINDOW_SECONDS * 5);
        return true;
    }
}
