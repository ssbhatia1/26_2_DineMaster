package com.dinemaster.auth.service;

import com.dinemaster.auth.entity.AuthAuditLog;
import com.dinemaster.auth.repository.AuthAuditLogRepository;
import org.springframework.stereotype.Service;

@Service
public class AuthAuditService {
    private final AuthAuditLogRepository repository;

    public AuthAuditService(AuthAuditLogRepository repository) { this.repository = repository; }

    public void record(Long userId, String username, String action, boolean success) {
        repository.save(new AuthAuditLog(userId, username, action, success));
    }
}
