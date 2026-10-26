package com.dinemaster.dto;

import com.dinemaster.entity.Order;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

public record OrderResponse(
        Long id,
        Long restaurantId,
        Long tableId,
        Long customerId,
        Long waiterId,
        BigDecimal totalAmount,
        BigDecimal discountAmount,
        String status,
        String type,
        OffsetDateTime orderTime,
        String notes,
        String paymentStatus,
        String paymentMethod,
        String customerName,
        String customerPhone,
        String orderTaker,
        String deliveredBy,
        OffsetDateTime deliveryTimestamp,
        Integer guestCount) {

    public static OrderResponse from(Order order) {
        return new OrderResponse(
                order.getId(),
                order.getRestaurant() == null ? null : order.getRestaurant().getId(),
                order.getDiningTable() == null ? null : order.getDiningTable().getId(),
                order.getCustomer() == null ? null : order.getCustomer().getId(),
                order.getWaiter() == null ? null : order.getWaiter().getId(),
                order.getTotalAmount(),
                order.getDiscountAmount(),
                order.getStatus(),
                order.getType(),
                order.getOrderTime(),
                order.getNotes(),
                order.getPaymentStatus(),
                order.getPaymentMethod(),
                order.getCustomerName(),
                order.getCustomerPhone(),
                order.getOrderTaker(),
                order.getDeliveredBy(),
                order.getDeliveryTimestamp(),
                order.getGuestCount());
    }
}
