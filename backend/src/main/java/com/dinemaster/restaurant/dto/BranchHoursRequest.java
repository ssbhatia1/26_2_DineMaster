package com.dinemaster.restaurant.dto;

import jakarta.validation.constraints.NotNull;
import java.time.DayOfWeek;
import java.time.LocalTime;

public record BranchHoursRequest(
        @NotNull DayOfWeek weekday,
        LocalTime openTime,
        LocalTime closeTime,
        boolean closed) { }
