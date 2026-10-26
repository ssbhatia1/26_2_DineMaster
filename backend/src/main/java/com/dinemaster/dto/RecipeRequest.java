package com.dinemaster.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.math.BigDecimal;

public record RecipeRequest(
        @NotNull @Positive Long productId,
        @NotNull @Positive Long ingredientId,
        @NotNull @DecimalMin(value = "0.0", inclusive = false) BigDecimal quantityUsed) {
}