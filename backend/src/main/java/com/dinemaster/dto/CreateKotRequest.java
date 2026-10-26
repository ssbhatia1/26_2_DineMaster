package com.dinemaster.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public record CreateKotRequest(
        @NotNull @Positive Long orderId,
        String kotNumber,
        String priority,
        @Positive Integer estimatedTime) {
}