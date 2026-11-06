package com.dinemaster.orders.dto;



import com.dinemaster.orders.entity.Order;

import jakarta.validation.constraints.NotBlank;

public record OrderStatusRequest(
        @NotBlank(message = "Order status is required") String status) {
}
