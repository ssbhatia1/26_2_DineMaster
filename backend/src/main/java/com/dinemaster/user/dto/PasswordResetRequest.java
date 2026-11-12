package com.dinemaster.user.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record PasswordResetRequest(@NotBlank @Size(min = 10, max = 128) String temporaryPassword,
        @Size(max = 500) String reason) { }
