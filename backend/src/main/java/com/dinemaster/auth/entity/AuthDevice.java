package com.dinemaster.auth.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "auth_devices")
public class AuthDevice {
    @Id private UUID id;
    @Column(name = "user_id") private Long userId;
    @Column(name = "tenant_id") private Long tenantId;
    @Column(name = "branch_id") private Long branchId;
    @Column(nullable = false, length = 100) private String label = "Unknown device";
    @Column(nullable = false, length = 50) private String platform = "UNKNOWN";
    @Column(nullable = false) private boolean active = true;
    @Column(name = "created_at", nullable = false) private OffsetDateTime createdAt;
    @Column(name = "last_seen_at") private OffsetDateTime lastSeenAt;

    protected AuthDevice() { }
    public AuthDevice(UUID id, Long userId, Long tenantId, String label) {
        this.id = id; this.userId = userId; this.tenantId = tenantId;
        this.label = label == null || label.isBlank() ? "Unknown device" : label.trim();
        this.createdAt = OffsetDateTime.now(); this.lastSeenAt = this.createdAt;
    }
    public UUID getId() { return id; }
    public Long getUserId() { return userId; }
    public Long getTenantId() { return tenantId; }
    public Long getBranchId() { return branchId; }
    public void setBranchId(Long branchId) { this.branchId = branchId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getLabel() { return label; }
    public String getPlatform() { return platform; }
    public void setPlatform(String platform) {
        this.platform = platform == null || platform.isBlank() ? "UNKNOWN" : platform.trim();
    }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public boolean isActive() { return active; }
    public void setActive(boolean active) { this.active = active; }
    public OffsetDateTime getLastSeenAt() { return lastSeenAt; }
    public void setLastSeenAt(OffsetDateTime value) { this.lastSeenAt = value; }
}
