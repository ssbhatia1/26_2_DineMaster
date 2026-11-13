package com.dinemaster.diningtable.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.PositiveOrZero;

public record TableStatusRequest(@NotBlank String status, @PositiveOrZero Integer version) { }
