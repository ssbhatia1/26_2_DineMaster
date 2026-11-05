package com.dinemaster.auth.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "auth_audit_logs")
public class AuthAuditLog {
    @Id private UUID id;
    @Column(name = "user_id") private Long userId;
    @Column(nullable = false, length = 100) private String username;
    @Column(nullable = false, length = 50) private String action;
    @Column(nullable = false) private boolean success;
    @Column(name = "created_at", nullable = false) private OffsetDateTime createdAt;

    protected AuthAuditLog() { }
    public AuthAuditLog(Long userId, String username, String action, boolean success) {
        this.id = UUID.randomUUID();
        this.userId = userId;
        this.username = username == null ? "unknown" : username;
        this.action = action;
        this.success = success;
        this.createdAt = OffsetDateTime.now();
    }
}
