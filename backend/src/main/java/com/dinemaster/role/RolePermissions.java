package com.dinemaster.role;

import java.util.LinkedHashSet;
import java.util.Set;

/** Default permission-code grants for the built-in roles in the M1/RBAC design. */
public final class RolePermissions {
    private RolePermissions() { }

    public static Set<String> forRole(String rawRole) {
        String role = Roles.canonical(rawRole);
        Set<String> permissions = new LinkedHashSet<>();
        switch (role) {
            case "OWNER" -> permissions.addAll(Set.of(
                    "branch:view", "branch:create", "branch:update", "settings:view", "settings:update",
                    "backup:create", "backup:restore", "user:view", "user:create", "user:update",
                    "user:deactivate", "role:assign", "audit:view", "session:revoke", "device:activate", "table:view",
                    "table:update_status", "table:manage_layout", "table:assign_waiter", "reservation:view",
                    "reservation:create", "reservation:update", "menu:view", "menu:manage",
                    "menu:toggle_availability", "recipe:view", "recipe:manage", "order:create", "order:view",
                    "order:update", "order:cancel", "order:void", "order:park", "order:reopen",
                    "discount:apply", "discount:approve", "kot:view", "kot:update_status", "kot:reprint",
                    "bill:generate", "bill:reprint", "payment:record", "payment:refund", "shift:open",
                    "shift:close", "inventory:view", "inventory:receive", "inventory:adjust", "inventory:count",
                    "supplier:view", "supplier:manage", "expense:view", "expense:create", "expense:approve",
                    "offer:view", "offer:manage", "customer:view", "customer:manage", "dashboard:view",
                    "report:sales", "report:kitchen", "report:inventory", "report:finance", "report:export",
                    "notification:view", "notification:manage", "sync:view_status", "sync:resolve_conflict"));
            case "SUPER_ADMIN" -> permissions.addAll(Set.of(
                    "tenant:view", "tenant:create", "tenant:suspend", "tenant:activate", "role:assign",
                    "licence:manage", "support:grant_access"));
            case "MANAGER" -> permissions.addAll(Set.of(
                    "branch:view", "settings:view", "settings:update", "backup:create", "user:view", "user:create",
                    "user:update", "user:deactivate", "audit:view", "session:revoke", "device:activate", "table:view",
                    "table:update_status", "table:manage_layout", "table:assign_waiter", "reservation:view",
                    "reservation:create", "reservation:update", "menu:view", "menu:manage", "menu:toggle_availability",
                    "recipe:view", "recipe:manage", "order:create", "order:view", "order:update", "order:cancel",
                    "order:void", "order:park", "order:reopen", "discount:apply", "discount:approve", "kot:view",
                    "kot:update_status", "kot:reprint", "bill:generate", "bill:reprint", "payment:record",
                    "payment:refund", "shift:open", "shift:close", "inventory:view", "inventory:receive",
                    "inventory:adjust", "inventory:count", "supplier:view", "supplier:manage", "expense:view",
                    "expense:create", "offer:view", "offer:manage", "customer:view", "customer:manage",
                    "dashboard:view", "report:sales", "report:kitchen", "report:inventory", "report:export",
                    "notification:view", "notification:manage", "sync:view_status", "sync:resolve_conflict"));
            case "CASHIER" -> permissions.addAll(Set.of(
                    "table:view", "table:update_status", "table:assign_waiter", "reservation:view", "reservation:create",
                    "reservation:update", "menu:view", "order:create", "order:view", "order:update", "order:cancel",
                    "order:park", "order:reopen", "discount:apply", "kot:view", "kot:reprint", "bill:generate",
                    "bill:reprint", "payment:record", "shift:open", "shift:close", "offer:view", "customer:view",
                    "customer:manage", "dashboard:view", "report:sales", "notification:view", "sync:view_status"));
            case "WAITER" -> permissions.addAll(Set.of(
                    "table:view", "reservation:view", "reservation:create", "reservation:update", "menu:view",
                    "order:create", "order:view", "order:update", "order:cancel", "order:park", "order:reopen",
                    "kot:view", "kot:update_status", "kot:reprint", "customer:view", "notification:view"));
            case "CHEF" -> permissions.addAll(Set.of(
                    "menu:view", "menu:toggle_availability", "recipe:view", "order:view", "kot:view",
                    "kot:update_status", "kot:reprint", "inventory:view", "dashboard:view", "report:kitchen",
                    "notification:view"));
            case "INVENTORY_MANAGER" -> permissions.addAll(Set.of(
                    "branch:view", "menu:view", "recipe:view", "inventory:view", "inventory:receive",
                    "inventory:adjust", "inventory:count", "supplier:view", "supplier:manage", "expense:view",
                    "expense:create", "dashboard:view", "report:inventory", "report:export", "notification:view"));
            default -> { }
        }
        return Set.copyOf(permissions);
    }
}
