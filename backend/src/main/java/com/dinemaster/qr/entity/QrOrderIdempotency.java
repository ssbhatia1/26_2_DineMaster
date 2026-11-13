package com.dinemaster.qr.entity;

import com.dinemaster.orders.entity.Order;
import jakarta.persistence.*;

@Entity
@Table(name = "qr_order_idempotency", uniqueConstraints = @UniqueConstraint(
        name = "uq_qr_idempotency_session_key", columnNames = {"session_id", "idempotency_key"}))
public class QrOrderIdempotency {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false) @JoinColumn(name = "session_id", nullable = false)
    private TableSession session;
    @Column(name = "idempotency_key", nullable = false, length = 100)
    private String idempotencyKey;
    @ManyToOne(fetch = FetchType.LAZY, optional = false) @JoinColumn(name = "order_id", nullable = false)
    private Order order;
    public Long getId() { return id; }
    public TableSession getSession() { return session; }
    public void setSession(TableSession session) { this.session = session; }
    public String getIdempotencyKey() { return idempotencyKey; }
    public void setIdempotencyKey(String idempotencyKey) { this.idempotencyKey = idempotencyKey; }
    public Order getOrder() { return order; }
    public void setOrder(Order order) { this.order = order; }
}
