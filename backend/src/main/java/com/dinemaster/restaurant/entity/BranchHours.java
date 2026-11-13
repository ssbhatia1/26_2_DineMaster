package com.dinemaster.restaurant.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.DayOfWeek;
import java.time.LocalTime;

@Entity
@Table(name = "branch_hours")
public class BranchHours {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "branch_id", nullable = false)
    private Long branchId;

    @Column(nullable = false, length = 10)
    private DayOfWeek weekday;

    @Column(name = "open_time")
    private LocalTime openTime;

    @Column(name = "close_time")
    private LocalTime closeTime;

    @Column(name = "is_closed", nullable = false)
    private boolean closed;

    protected BranchHours() { }

    public BranchHours(Long branchId, DayOfWeek weekday, LocalTime openTime, LocalTime closeTime, boolean closed) {
        this.branchId = branchId;
        this.weekday = weekday;
        this.openTime = openTime;
        this.closeTime = closeTime;
        this.closed = closed;
    }

    public Long getId() { return id; }
    public Long getBranchId() { return branchId; }
    public DayOfWeek getWeekday() { return weekday; }
    public LocalTime getOpenTime() { return openTime; }
    public LocalTime getCloseTime() { return closeTime; }
    public boolean isClosed() { return closed; }
}
