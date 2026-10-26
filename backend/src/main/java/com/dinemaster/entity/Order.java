
package com.dinemaster.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Entity
@Table(name = "orders")
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "table_id")
    private DiningTable diningTable;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "customer_id")
    private Customer customer;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "waiter_id")
    private User waiter;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "restaurant_id")
    private Restaurant restaurant;

    @Column(name = "total_amount", nullable = false, precision = 12, scale = 2)
    private BigDecimal totalAmount = BigDecimal.ZERO;

    @Column(name = "discount_amount", nullable = false, precision = 12, scale = 2)
    private BigDecimal discountAmount = BigDecimal.ZERO;

    @Column(nullable = false, length = 30)
    private String status = "Pending";

    @Column(name = "type", nullable = false, length = 30)
    private String type = "Dine In";

    @Column(name = "order_time", nullable = false)
    private OffsetDateTime orderTime;

    @Column(columnDefinition = "TEXT")
    private String notes;

    @Column(name = "payment_status", nullable = false, length = 30)
    private String paymentStatus = "Unpaid";

    @Column(name = "payment_method", length = 50)
    private String paymentMethod;

    @Column(name = "customer_name", length = 150)
    private String customerName;

    @Column(name = "customer_phone", length = 30)
    private String customerPhone;

    @Column(name = "order_taker", length = 150)
    private String orderTaker;

    @Column(name = "delivered_by", length = 150)
    private String deliveredBy;

    @Column(name = "delivery_timestamp")
    private OffsetDateTime deliveryTimestamp;

    @Column(name = "guest_count")
    private Integer guestCount;

    @PrePersist
    protected void onCreate() {
        if (orderTime == null) {
            orderTime = OffsetDateTime.now();
        }
    }

    public Order() {
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public DiningTable getDiningTable() { return diningTable; }
    public void setDiningTable(DiningTable diningTable) {
        this.diningTable = diningTable;
    }

    public Customer getCustomer() { return customer; }
    public void setCustomer(Customer customer) { this.customer = customer; }

    public User getWaiter() { return waiter; }
    public void setWaiter(User waiter) { this.waiter = waiter; }

    public Restaurant getRestaurant() { return restaurant; }
    public void setRestaurant(Restaurant restaurant) {
        this.restaurant = restaurant;
    }

    public BigDecimal getTotalAmount() { return totalAmount; }
    public void setTotalAmount(BigDecimal totalAmount) {
        this.totalAmount = totalAmount;
    }

    public BigDecimal getDiscountAmount() { return discountAmount; }
    public void setDiscountAmount(BigDecimal discountAmount) {
        this.discountAmount = discountAmount;
    }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }

    public OffsetDateTime getOrderTime() { return orderTime; }
    public void setOrderTime(OffsetDateTime orderTime) {
        this.orderTime = orderTime;
    }

    public String getNotes() { return notes; }
    public void setNotes(String notes) { this.notes = notes; }

    public String getPaymentStatus() { return paymentStatus; }
    public void setPaymentStatus(String paymentStatus) {
        this.paymentStatus = paymentStatus;
    }

    public String getPaymentMethod() { return paymentMethod; }
    public void setPaymentMethod(String paymentMethod) {
        this.paymentMethod = paymentMethod;
    }

    public String getCustomerName() { return customerName; }
    public void setCustomerName(String customerName) {
        this.customerName = customerName;
    }

    public String getCustomerPhone() { return customerPhone; }
    public void setCustomerPhone(String customerPhone) {
        this.customerPhone = customerPhone;
    }

    public String getOrderTaker() { return orderTaker; }
    public void setOrderTaker(String orderTaker) {
        this.orderTaker = orderTaker;
    }

    public String getDeliveredBy() { return deliveredBy; }
    public void setDeliveredBy(String deliveredBy) {
        this.deliveredBy = deliveredBy;
    }

    public OffsetDateTime getDeliveryTimestamp() { return deliveryTimestamp; }
    public void setDeliveryTimestamp(OffsetDateTime deliveryTimestamp) {
        this.deliveryTimestamp = deliveryTimestamp;
    }

    public Integer getGuestCount() { return guestCount; }
    public void setGuestCount(Integer guestCount) {
        this.guestCount = guestCount;
    }
}
