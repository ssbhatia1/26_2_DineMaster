package com.dinemaster.qr.entity;

import jakarta.persistence.*;
import java.time.OffsetDateTime;

@Entity
@Table(name = "guest_service_requests")
public class GuestServiceRequest {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false) @JoinColumn(name = "session_id", nullable = false)
    private TableSession session;
    @Column(name = "request_type", nullable = false, length = 30)
    private String requestType = "CALL_WAITER";
    @Column(nullable = false, length = 20)
    private String status = "OPEN";
    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;
    @Column(name = "acknowledged_at")
    private OffsetDateTime acknowledgedAt;
    @PrePersist void beforeInsert() { if (createdAt == null) createdAt = OffsetDateTime.now(); }
    public Long getId() { return id; }
    public TableSession getSession() { return session; }
    public void setSession(TableSession session) { this.session = session; }
    public String getRequestType() { return requestType; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public void setAcknowledgedAt(OffsetDateTime acknowledgedAt) { this.acknowledgedAt = acknowledgedAt; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
}
