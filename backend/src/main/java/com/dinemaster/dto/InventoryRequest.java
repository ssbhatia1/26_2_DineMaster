package com.dinemaster.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.time.LocalDate;

public record InventoryRequest(
        @NotBlank String itemName,
        @NotNull @DecimalMin("0.0") BigDecimal currentStock,
        @NotBlank String unit,
        @NotNull @DecimalMin("0.0") BigDecimal lowStockThreshold,
        LocalDate expiryDate,
        @NotNull Long restaurantId) {
}