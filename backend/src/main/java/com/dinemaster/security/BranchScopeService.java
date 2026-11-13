package com.dinemaster.security;

import com.dinemaster.booking.repository.BookingRepository;
import com.dinemaster.catalog.repository.ProductRepository;
import com.dinemaster.diningtable.repository.DiningTableRepository;
import com.dinemaster.inventory.repository.InventoryRepository;
import com.dinemaster.kitchen.repository.KotRepository;
import com.dinemaster.orders.repository.OrderRepository;
import com.dinemaster.recipe.repository.RecipeRepository;
import com.dinemaster.restaurant.repository.RestaurantRepository;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserBranchRepository;
import com.dinemaster.user.repository.UserRepository;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;

@Service
public class BranchScopeService {
    private final UserRepository users;
    private final UserBranchRepository userBranches;
    private final RestaurantRepository branches;
    private final ProductRepository products;
    private final DiningTableRepository tables;
    private final OrderRepository orders;
    private final BookingRepository bookings;
    private final InventoryRepository inventory;
    private final KotRepository kitchenTickets;
    private final RecipeRepository recipes;

    public BranchScopeService(UserRepository users, UserBranchRepository userBranches,
            RestaurantRepository branches, ProductRepository products, DiningTableRepository tables,
            OrderRepository orders, BookingRepository bookings, InventoryRepository inventory,
            KotRepository kitchenTickets, RecipeRepository recipes) {
        this.users = users; this.userBranches = userBranches; this.branches = branches;
        this.products = products; this.tables = tables; this.orders = orders; this.bookings = bookings;
        this.inventory = inventory; this.kitchenTickets = kitchenTickets; this.recipes = recipes;
    }

    public User requireUser(Authentication authentication) {
        if (authentication == null || authentication.getName() == null)
            throw new AccessDeniedException("Authentication is required");
        return users.findByUsername(authentication.getName())
                .filter(User::isActive).orElseThrow(() -> new AccessDeniedException("Active user is required"));
    }

    public void requireBranch(Authentication authentication, Long branchId) {
        User user = requireUser(authentication);
        boolean belongsToTenant = belongsToTenant(user, branchId);
        boolean hasBranchAccess = com.dinemaster.role.Roles.matches(user.getRole(), "OWNER")
                || branchId != null && userBranches.isAssigned(user.getId(), branchId);
        if (!belongsToTenant || !hasBranchAccess) {
            throw new AccessDeniedException("Branch is outside the user's assigned scope");
        }
    }

    public boolean belongsToTenant(User user, Long branchId) {
        return user != null && branchId != null && user.getTenantId() != null
                && branches.findById(branchId)
                        .filter(branch -> user.getTenantId().equals(branch.getTenantId())).isPresent();
    }

    public boolean canViewUser(User actor, User target) {
        if (actor == null || target == null || actor.getTenantId() == null
                || !actor.getTenantId().equals(target.getTenantId())) {
            return false;
        }
        if (com.dinemaster.role.Roles.matches(actor.getRole(), "OWNER")) {
            return !com.dinemaster.role.Roles.matches(target.getRole(), "SUPER_ADMIN");
        }
        if (!com.dinemaster.role.Roles.matches(actor.getRole(), "MANAGER")) {
            return false;
        }
        return sharesManagedBranch(actor, target);
    }

    public boolean canManageUser(User actor, User target) {
        if (!canViewUser(actor, target)) {
            return false;
        }
        if (com.dinemaster.role.Roles.matches(actor.getRole(), "OWNER")) {
            return true;
        }
        return com.dinemaster.role.Roles.matches(actor.getRole(), "MANAGER")
                && java.util.Set.of("CASHIER", "WAITER", "CHEF", "INVENTORY_MANAGER", "STAFF")
                        .stream().anyMatch(role -> com.dinemaster.role.Roles.matches(target.getRole(), role));
    }

    private boolean sharesManagedBranch(User actor, User target) {
        java.util.Set<Long> branchesForActor = new java.util.HashSet<>(userBranches.findBranchIds(actor.getId()));
        return userBranches.findBranchIds(target.getId()).stream().anyMatch(branchesForActor::contains);
    }

    public Long branchForResource(String uri, Long id) {
        String[] path = uri.split("/");
        if (path.length < 5 || id == null) return null;
        return switch (path[3]) {
            case "branches" -> branches.findById(id).map(branch -> branch.getId()).orElse(null);
            case "products" -> products.findById(id).map(product -> product.getRestaurantId()).orElse(null);
            case "tables" -> tables.findById(id).map(table -> table.getRestaurant() == null ? null : table.getRestaurant().getId()).orElse(null);
            case "orders" -> orders.findById(id).map(order -> order.getRestaurant() == null ? null : order.getRestaurant().getId()).orElse(null);
            case "reservations" -> bookings.findById(id).map(booking -> booking.getRestaurant() == null ? null : booking.getRestaurant().getId()).orElse(null);
            case "inventory" -> inventory.findById(id).map(item -> item.getRestaurant() == null ? null : item.getRestaurant().getId()).orElse(null);
            case "kitchen-tickets" -> kitchenTickets.findById(id)
                    .map(kot -> kot.getOrder().getRestaurant() == null ? null : kot.getOrder().getRestaurant().getId()).orElse(null);
            case "recipes" -> recipes.findById(id)
                    .map(recipe -> recipe.getProduct().getRestaurantId()).orElse(null);
            default -> null;
        };
    }

    public Long branchForProduct(Long productId) {
        return productId == null ? null : products.findById(productId).map(product -> product.getRestaurantId()).orElse(null);
    }
}
