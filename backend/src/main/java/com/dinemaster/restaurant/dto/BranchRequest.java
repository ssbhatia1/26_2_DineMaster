package com.dinemaster.restaurant.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record BranchRequest(
        @NotBlank @Size(max = 20) @Pattern(regexp = "[A-Za-z0-9_-]+") String code,
        @NotBlank @Size(max = 150) String name,
        @Size(max = 5000) String address,
        @Size(max = 30) String phone,
        @NotBlank @Size(max = 50) String timezone) { }
