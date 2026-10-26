
package com.dinemaster.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

public class CreateOrderRequest {

    @NotNull(message = "Restaurant ID is required")
    @Positive(message = "Restaurant ID must be positive")
    private Long restaurantId;

    @Positive(message = "Table ID must be positive")
    private Long tableId;

    @Positive(message = "Customer ID must be positive")
    private Long customerId;

    @Positive(message = "Waiter ID must be positive")
    private Long waiterId;

    @Size(max = 30, message = "Order type cannot exceed 30 characters")
    private String type = "Dine In";

    @Size(max = 2000, message = "Order notes cannot exceed 2000 characters")
    private String notes;

    @Positive(message = "Guest count must be positive")
    private Integer guestCount;

    private BigDecimal discountAmount = BigDecimal.ZERO;

    @Valid
    @NotEmpty(message = "At least one order item is required")
    private List<OrderItemRequest> items = new ArrayList<>();

    public CreateOrderRequest() {
    }

    public Long getRestaurantId() { return restaurantId; }
    public void setRestaurantId(Long restaurantId) {
        this.restaurantId = restaurantId;
    }

    public Long getTableId() { return tableId; }
    public void setTableId(Long tableId) { this.tableId = tableId; }

    public Long getCustomerId() { return customerId; }
    public void setCustomerId(Long customerId) { this.customerId = customerId; }

    public Long getWaiterId() { return waiterId; }
    public void setWaiterId(Long waiterId) { this.waiterId = waiterId; }

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }

    public String getNotes() { return notes; }
    public void setNotes(String notes) { this.notes = notes; }

    public Integer getGuestCount() { return guestCount; }
    public void setGuestCount(Integer guestCount) { this.guestCount = guestCount; }

    public BigDecimal getDiscountAmount() { return discountAmount; }
    public void setDiscountAmount(BigDecimal discountAmount) {
        this.discountAmount = discountAmount;
    }

    public List<OrderItemRequest> getItems() { return items; }
    public void setItems(List<OrderItemRequest> items) { this.items = items; }
}
