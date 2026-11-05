package com.dinemaster.catalog.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotNull;

public record ProductAvailabilityRequest(
        @JsonProperty("is_available") @NotNull(message = "is_available is required") Boolean available) {
}
