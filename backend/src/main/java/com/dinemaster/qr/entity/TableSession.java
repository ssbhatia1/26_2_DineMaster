package com.dinemaster.qr.entity;

import com.dinemaster.diningtable.entity.DiningTable;
import com.dinemaster.restaurant.entity.Restaurant;
import jakarta.persistence.*;
import java.time.OffsetDateTime;

@Entity
@Table(name = "table_sessions")
public class TableSession {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "branch_id", nullable = false)
    private Restaurant branch;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "table_id", nullable = false)
    private DiningTable table;

    @Column(name = "token_hash", nullable = false, unique = true, length = 64)
    private String tokenHash;

    @Column(name = "opened_at", nullable = false)
    private OffsetDateTime openedAt;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "closed_at")
    private OffsetDateTime closedAt;

    @PrePersist
    void beforeInsert() { if (openedAt == null) openedAt = OffsetDateTime.now(); }

    public Long getId() { return id; }
    public Restaurant getBranch() { return branch; }
    public void setBranch(Restaurant branch) { this.branch = branch; }
    public DiningTable getTable() { return table; }
    public void setTable(DiningTable table) { this.table = table; }
    public String getTokenHash() { return tokenHash; }
    public void setTokenHash(String tokenHash) { this.tokenHash = tokenHash; }
    public OffsetDateTime getOpenedAt() { return openedAt; }
    public OffsetDateTime getExpiresAt() { return expiresAt; }
    public void setExpiresAt(OffsetDateTime expiresAt) { this.expiresAt = expiresAt; }
    public OffsetDateTime getClosedAt() { return closedAt; }
    public void setClosedAt(OffsetDateTime closedAt) { this.closedAt = closedAt; }
    public boolean isValidAt(OffsetDateTime now) { return closedAt == null && expiresAt.isAfter(now); }
}
