package com.dinemaster.user.dto;



import com.dinemaster.role.Roles;
import com.dinemaster.user.entity.User;

import java.time.OffsetDateTime;

public record UserResponse(Long id, String name, String username, String role,
        boolean active, String contactDetails, String shiftTiming, OffsetDateTime createdAt) {
    public static UserResponse from(User user) {
        return new UserResponse(user.getId(), user.getName(), user.getUsername(), Roles.canonical(user.getRole()),
                user.isActive(), user.getContactDetails(), user.getShiftTiming(), user.getCreatedAt());
    }
}
