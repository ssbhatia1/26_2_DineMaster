package com.dinemaster.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.time.OffsetDateTime;

public record BookingRequest(
        @NotNull @Positive Long tableId,
        Long customerId,
        String customerName,
        String customerPhone,
        @NotNull @Positive Integer guestCount,
        @NotNull OffsetDateTime bookingTime,
        String status,
        String notes,
        @NotNull @Positive Long restaurantId) {
}