package com.dinemaster.auth.dto;



import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record LoginRequest(@NotBlank @Size(min = 3, max = 60) String username,
        @NotBlank @Size(max = 128) String password,
        @Size(max = 100) String deviceLabel) {
}
