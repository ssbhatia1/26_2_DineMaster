package com.dinemaster.tenant.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record TenantCreateRequest(
        @NotBlank @Size(max = 150) String name,
        @NotBlank @Size(max = 150) String ownerName,
        @NotBlank @Size(max = 100) String ownerUsername,
        @NotBlank @Size(min = 10, max = 128) String ownerPassword) { }
