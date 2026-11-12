package com.dinemaster.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record DeviceActivationRequest(@NotBlank @Size(max = 100) String activationCode,
        @NotBlank @Size(max = 50) String platform,
        @NotBlank @Size(max = 100) String deviceName) { }
