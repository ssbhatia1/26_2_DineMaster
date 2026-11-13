package com.dinemaster.role.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.NotBlank;
import java.util.Set;

public record RolePermissionUpdateRequest(@NotNull Set<@NotBlank String> permissions) { }
