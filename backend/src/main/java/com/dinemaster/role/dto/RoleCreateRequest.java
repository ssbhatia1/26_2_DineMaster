package com.dinemaster.role.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.Set;

public record RoleCreateRequest(
        @NotBlank @Pattern(regexp = "[A-Za-z][A-Za-z0-9_]*") @Size(max = 50) String code,
        @NotBlank @Size(max = 100) String name,
        Set<@NotBlank @Size(max = 100) String> permissions) { }
