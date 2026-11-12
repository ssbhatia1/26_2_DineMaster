package com.dinemaster.user.dto;



import com.dinemaster.user.entity.User;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.util.List;

public record UserRequest(
        @NotBlank @Size(max = 150) String name,
        @NotBlank @Size(max = 100) String username,
        @Size(max = 255) String password,
        @NotBlank @Size(max = 30) String role,
        Boolean active,
        String contactDetails,
        String shiftTiming,
        @Size(max = 50) List<@Positive Long> branchIds) {
}
