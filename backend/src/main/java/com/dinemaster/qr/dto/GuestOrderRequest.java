package com.dinemaster.qr.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.util.List;

public record GuestOrderRequest(
        @NotEmpty @Size(max = 20) List<@Valid Item> items,
        @Size(max = 1000) String notes) {
    public record Item(@NotNull @Positive Long productId,
                       @NotNull @Min(1) @Max(10) Integer quantity,
                       @Size(max = 500) String notes) {}
}
