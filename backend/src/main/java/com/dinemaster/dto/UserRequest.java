package com.dinemaster.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record UserRequest(
        @NotBlank @Size(max = 150) String name,
        @NotBlank @Size(max = 100) String username,
        @Size(max = 255) String password,
        @NotBlank @Size(max = 30) String role,
        Boolean active,
        String contactDetails,
        String shiftTiming) {
}