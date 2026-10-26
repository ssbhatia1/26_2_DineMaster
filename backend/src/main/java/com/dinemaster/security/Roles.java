package com.dinemaster.security;

import java.util.Locale;

public final class Roles {
    private Roles() {
    }

    public static String canonical(String role) {
        if (role == null || role.isBlank()) {
            return "STAFF";
        }
        String value = role.trim().toUpperCase(Locale.ROOT).replace(' ', '_');
        if (value.startsWith("ROLE_")) {
            value = value.substring(5);
        }
        return switch (value) {
            case "OWNER" -> "OWNER";
            case "MANAGER" -> "MANAGER";
            case "CASHIER" -> "CASHIER";
            case "WAITER" -> "WAITER";
            case "CHEF", "COOK" -> "CHEF";
            case "EMPLOYEE", "STAFF" -> "STAFF";
            default -> value;
        };
    }

    public static boolean matches(String actualRole, String selectedRole) {
        return canonical(actualRole).equals(canonical(selectedRole));
    }
}
