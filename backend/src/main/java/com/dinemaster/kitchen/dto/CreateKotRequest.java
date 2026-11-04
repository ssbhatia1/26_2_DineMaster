package com.dinemaster.kitchen.dto;



import com.dinemaster.kitchen.entity.Kot;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public record CreateKotRequest(
        @NotNull @Positive Long orderId,
        String kotNumber,
        String priority,
        @Positive Integer estimatedTime) {
}
