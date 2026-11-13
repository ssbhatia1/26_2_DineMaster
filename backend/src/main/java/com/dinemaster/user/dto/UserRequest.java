package com.dinemaster.user.dto;



import com.dinemaster.user.entity.User;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import jakarta.validation.constraints.Email;
import java.util.List;
import java.time.LocalDate;
import com.fasterxml.jackson.annotation.JsonAlias;

public record UserRequest(
        @JsonAlias("fullName") @NotBlank @Size(max = 150) String name,
        @NotBlank @Size(max = 100) String username,
        @Size(max = 255) String password,
        @Size(max = 30) String role,
        @Size(max = 10) List<@Size(min = 2, max = 50) String> roleCodes,
        Boolean active,
        String contactDetails,
        String shiftTiming,
        @Size(max = 50) List<@Positive Long> branchIds,
        @JsonAlias("phone") String phone,
        @Email @Size(max = 255) String email,
        @Size(max = 40) String employeeCode,
        LocalDate joinedOn) {

    public String effectiveRole() {
        if (role != null && !role.isBlank()) return role;
        return roleCodes != null && roleCodes.size() == 1 ? roleCodes.get(0) : null;
    }

    public String effectiveContactDetails() {
        return contactDetails != null ? contactDetails : phone;
    }
}
