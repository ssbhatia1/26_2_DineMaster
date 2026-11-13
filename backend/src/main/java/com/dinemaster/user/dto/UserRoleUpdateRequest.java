package com.dinemaster.user.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;

public record UserRoleUpdateRequest(
        @NotEmpty @Size(max = 10) List<@Size(min = 2, max = 50) String> roleCodes) {
}
