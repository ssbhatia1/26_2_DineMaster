package com.dinemaster.inventory.dto;



import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.math.BigDecimal;

public record StockAdjustmentRequest(
        @NotBlank @Pattern(regexp = "(?i)add|deduct|set", message = "Mode must be add, deduct, or set") String mode,
        @NotNull @DecimalMin("0.0") BigDecimal quantity) {
}
