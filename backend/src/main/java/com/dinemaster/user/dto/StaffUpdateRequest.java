package com.dinemaster.user.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;

/** Editable staff profile fields. Identity, role, branch and account status use dedicated APIs. */
public record StaffUpdateRequest(
        @JsonAlias("name") @Size(max = 150) String fullName,
        @Email @Size(max = 255) String email,
        @JsonAlias("contactDetails") @Size(max = 30) String phone,
        @Size(max = 40) String employeeCode,
        LocalDate joinedOn,
        @Size(max = 50) String shiftTiming) {
}
