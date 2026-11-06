package com.dinemaster.inventory.dto;



import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.LocalDate;

public record InventoryRequest(
        @NotBlank @Size(max = 150) String itemName,
        @NotNull @DecimalMin("0.0") BigDecimal currentStock,
        @NotBlank @Size(max = 30) String unit,
        @NotNull @DecimalMin("0.0") BigDecimal lowStockThreshold,
        LocalDate expiryDate,
        @NotNull @Positive Long restaurantId) {
}
