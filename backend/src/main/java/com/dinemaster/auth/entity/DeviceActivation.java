package com.dinemaster.auth.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "auth_device_activations")
public class DeviceActivation {
    @Id private UUID id;
    @Column(name = "tenant_id", nullable = false) private Long tenantId;
    @Column(name = "branch_id", nullable = false) private Long branchId;
    @Column(name = "activation_code_hash", nullable = false, unique = true, length = 64) private String codeHash;
    @Column(name = "expires_at", nullable = false) private OffsetDateTime expiresAt;
    @Column(name = "consumed_at") private OffsetDateTime consumedAt;
    @Column(name = "created_at", nullable = false) private OffsetDateTime createdAt;
    protected DeviceActivation() { }
    public DeviceActivation(UUID id, Long tenantId, Long branchId, String codeHash, OffsetDateTime expiresAt) {
        this.id = id; this.tenantId = tenantId; this.branchId = branchId; this.codeHash = codeHash;
        this.expiresAt = expiresAt; this.createdAt = OffsetDateTime.now();
    }
    public UUID getId() { return id; }
    public Long getTenantId() { return tenantId; }
    public Long getBranchId() { return branchId; }
    public String getCodeHash() { return codeHash; }
    public OffsetDateTime getExpiresAt() { return expiresAt; }
    public OffsetDateTime getConsumedAt() { return consumedAt; }
    public void setConsumedAt(OffsetDateTime value) { consumedAt = value; }
}
