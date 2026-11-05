package com.dinemaster.orders.dto;
import com.dinemaster.orders.entity.OrderItem;


import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;

public record OrderItemResponse(
        Long id,
        @JsonProperty("order_id") Long orderId,
        @JsonProperty("product_id") Long productId,
        @JsonProperty("product_name") String productName,
        Integer quantity,
        BigDecimal price,
        String notes,
        String status,
        @JsonProperty("kot_id") Long kotId) {

    public static OrderItemResponse from(OrderItem item) {
        return new OrderItemResponse(
                item.getId(),
                item.getOrder() == null ? null : item.getOrder().getId(),
                item.getProduct() == null ? null : item.getProduct().getId(),
                item.getProduct() == null ? null : item.getProduct().getName(),
                item.getQuantity(),
                item.getPrice(),
                item.getNotes(),
                item.getStatus(),
                item.getKot() == null ? null : item.getKot().getId());
    }
}
