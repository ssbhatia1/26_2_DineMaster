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
    @Column(name = "actor_user_id") private Long actorUserId;
    @Column(name = "tenant_id") private Long tenantId;
    @Column(name = "branch_id") private Long branchId;
    @Column(length = 500) private String reason;

    protected AuthAuditLog() { }
    public AuthAuditLog(Long userId, String username, String action, boolean success) {
        this(userId, username, action, success, null, null, null, null);
    }

    public AuthAuditLog(Long userId, String username, String action, boolean success,
            Long actorUserId, Long tenantId, Long branchId, String reason) {
        this.id = UUID.randomUUID();
        this.userId = userId;
        this.username = username == null ? "unknown" : username;
        this.action = action;
        this.success = success;
        this.createdAt = OffsetDateTime.now();
        this.actorUserId = actorUserId;
        this.tenantId = tenantId;
        this.branchId = branchId;
        this.reason = reason;
    }

    public UUID getId() { return id; }
    public Long getUserId() { return userId; }
    public String getUsername() { return username; }
    public String getAction() { return action; }
    public boolean isSuccess() { return success; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public Long getActorUserId() { return actorUserId; }
    public Long getTenantId() { return tenantId; }
    public Long getBranchId() { return branchId; }
    public String getReason() { return reason; }
}
