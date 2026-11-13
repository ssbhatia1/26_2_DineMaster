package com.dinemaster.booking.dto;



import com.dinemaster.booking.entity.Booking;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;

public record BookingRequest(
        @NotNull @Positive Long tableId,
        @Positive Long customerId,
        @Size(max = 150) String customerName,
        @Size(max = 30) String customerPhone,
        @NotNull @Positive Integer guestCount,
        @NotNull OffsetDateTime bookingTime,
        @Pattern(regexp = "Pending|Confirmed|Cancelled|Completed", message = "Status must be Pending, Confirmed, Cancelled, or Completed") String status,
        @Size(max = 2000) String notes,
        @NotNull @Positive Long restaurantId) {
}
