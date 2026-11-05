package com.dinemaster.kitchen.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public record CreateKotRequest(
        @NotNull @Positive Long orderId,
        @Positive Long chefId,
        String kotNumber,
        String priority,
        @Positive Integer estimatedTime) {
}