package com.dinemaster.user.dto;



import com.dinemaster.user.entity.User;

import java.time.OffsetDateTime;
import java.util.Set;

public record UserResponse(Long id, String name, String username, String role,
        boolean active, String contactDetails, String shiftTiming, OffsetDateTime createdAt, Set<String> permissions) {
    public static UserResponse from(User user, Set<String> permissions) {
        return new UserResponse(user.getId(), user.getName(), user.getUsername(), com.dinemaster.role.Roles.canonical(user.getRole()),
                user.isActive(), user.getContactDetails(), user.getShiftTiming(), user.getCreatedAt(),
                permissions);
    }
}
