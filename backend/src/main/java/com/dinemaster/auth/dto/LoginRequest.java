package com.dinemaster.auth.dto;



import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.UUID;

public record LoginRequest(@NotBlank @Size(min = 2, max = 60) String tenantCode,
        @NotBlank @Size(min = 3, max = 60) String username,
        @NotBlank @Size(max = 128) String password,
        UUID deviceId) {
}
