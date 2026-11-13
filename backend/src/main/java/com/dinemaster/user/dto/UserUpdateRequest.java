package com.dinemaster.user.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record UserUpdateRequest(
        @NotBlank @Size(max = 150) String name,
        @NotBlank @Size(max = 100) String username,
        @Size(max = 255) String contactDetails,
        @Size(max = 50) String shiftTiming) {
}
