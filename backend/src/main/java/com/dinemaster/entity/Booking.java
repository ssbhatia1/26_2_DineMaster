package com.dinemaster.entity;

import jakarta.persistence.*;
import java.time.OffsetDateTime;

@Entity
@Table(name = "bookings")
public class Booking {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "table_id", nullable = false)
    private DiningTable table;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "customer_id")
    private Customer customer;
    @Column(name = "customer_name", length = 150)
    private String customerName;
    @Column(name = "customer_phone", length = 30)
    private String customerPhone;
    @Column(name = "guest_count", nullable = false)
    private Integer guestCount;
    @Column(name = "booking_time", nullable = false)
    private OffsetDateTime bookingTime;
    @Column(nullable = false, length = 30)
    private String status = "Pending";
    @Column(columnDefinition = "TEXT")
    private String notes;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "restaurant_id", nullable = false)
    private Restaurant restaurant;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public DiningTable getTable() {
        return table;
    }

    public void setTable(DiningTable table) {
        this.table = table;
    }

    public Customer getCustomer() {
        return customer;
    }

    public void setCustomer(Customer customer) {
        this.customer = customer;
    }

    public String getCustomerName() {
        return customerName;
    }

    public void setCustomerName(String value) {
        customerName = value;
    }

    public String getCustomerPhone() {
        return customerPhone;
    }

    public void setCustomerPhone(String value) {
        customerPhone = value;
    }

    public Integer getGuestCount() {
        return guestCount;
    }

    public void setGuestCount(Integer value) {
        guestCount = value;
    }

    public OffsetDateTime getBookingTime() {
        return bookingTime;
    }

    public void setBookingTime(OffsetDateTime value) {
        bookingTime = value;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String value) {
        status = value;
    }

    public String getNotes() {
        return notes;
    }

    public void setNotes(String value) {
        notes = value;
    }

    public Restaurant getRestaurant() {
        return restaurant;
    }

    public void setRestaurant(Restaurant value) {
        restaurant = value;
    }
}