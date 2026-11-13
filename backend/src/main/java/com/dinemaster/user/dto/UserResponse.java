package com.dinemaster.user.dto;



import com.dinemaster.user.entity.User;

import java.time.OffsetDateTime;
import java.util.Set;
import java.util.List;
import java.time.LocalDate;

public record UserResponse(Long id, String name, String username, String role,
        boolean active, String contactDetails, String shiftTiming, OffsetDateTime createdAt,
        List<Long> branchIds, boolean mustChangePassword, Set<String> permissions,
        String email, String employeeCode, LocalDate joinedOn, String fullName, String status) {
    public static UserResponse from(User user, Set<String> permissions) {
        return from(user, permissions, maskContactForRole(user), List.of());
    }

    public static UserResponse from(User user, Set<String> permissions, String visibleContactDetails) {
        return from(user, permissions, visibleContactDetails, List.of());
    }

    public static UserResponse from(User user, Set<String> permissions, List<Long> branchIds) {
        return from(user, permissions, maskContactForRole(user), branchIds);
    }

    public static UserResponse from(User user, Set<String> permissions,
            String visibleContactDetails, List<Long> branchIds) {
        return new UserResponse(user.getId(), user.getName(), user.getUsername(), com.dinemaster.role.Roles.canonical(user.getRole()),
                user.isActive(), visibleContactDetails, user.getShiftTiming(), user.getCreatedAt(),
                List.copyOf(branchIds), user.isMustChangePassword(),
                permissions, user.getEmail(), user.getEmployeeCode(), user.getJoinedOn(), user.getName(),
                user.isActive() ? "ACTIVE" : "INACTIVE");
    }

    private static String maskContactForRole(User user) {
        String contact = user.getContactDetails();
        if (contact == null || com.dinemaster.role.Roles.matches(user.getRole(), "OWNER")) return contact;
        String digits = contact.replaceAll("\\D", "");
        return digits.length() < 4 ? "****" : "******" + digits.substring(digits.length() - 4);
    }
}
