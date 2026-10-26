package com.dinemaster.dto;

import jakarta.validation.constraints.NotBlank;

public record OrderStatusRequest(
        @NotBlank(message = "Order status is required") String status) {
}