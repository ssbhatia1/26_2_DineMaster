package com.dinemaster.kitchen.dto;



import com.dinemaster.kitchen.entity.Kot;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

public record CreateKotRequest(
        @NotNull @Positive Long orderId,
        @Size(max = 50) String kotNumber,
        @Size(max = 30) String priority,
        @Positive Integer estimatedTime) {
}
