package com.dinemaster.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

public record StockAdjustmentRequest(
        @NotBlank String mode,
        @NotNull @DecimalMin("0.0") BigDecimal quantity) {
}