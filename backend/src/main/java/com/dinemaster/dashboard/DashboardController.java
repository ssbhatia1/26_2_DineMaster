package com.dinemaster.dashboard;

import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.restaurant.repository.RestaurantRepository;
import com.dinemaster.security.BranchScopeService;
import com.dinemaster.user.entity.User;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/dashboard")
public class DashboardController {
    private final DashboardReadRepository dashboard;
    private final RestaurantRepository branches;
    private final BranchScopeService branchScope;

    public DashboardController(DashboardReadRepository dashboard, RestaurantRepository branches,
            BranchScopeService branchScope) {
        this.dashboard = dashboard;
        this.branches = branches;
        this.branchScope = branchScope;
    }

    @GetMapping("/summary")
    @PreAuthorize("hasAuthority('dashboard:view')")
    public ResponseEntity<?> summary(@RequestParam Long branchId, @RequestParam(required = false) LocalDate date,
            Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        branchScope.requireBranch(authentication, branchId);
        Restaurant branch = branches.findById(branchId).orElse(null);
        if (branch == null || !branch.isActive()) return ResponseEntity.notFound().build();

        ZoneId zone = ZoneId.of(branch.getTimezone());
        LocalDate businessDate = date == null ? LocalDate.now(zone) : date;
        OffsetDateTime start = businessDate.atStartOfDay(zone).toOffsetDateTime();
        OffsetDateTime end = businessDate.plusDays(1).atStartOfDay(zone).toOffsetDateTime();

        Map<String, Object> metrics = new LinkedHashMap<>();
        boolean revenueVisible = canSeeRevenue(user, authentication);
        if (revenueVisible) {
            DashboardReadRepository.RevenueAggregate revenue = dashboard.revenue(branchId, start, end);
            metrics.put("revenue", Map.of("value", revenue.amount(), "currency", "INR", "visible", true));
            metrics.put("averageOrderValue", Map.of(
                    "value", revenue.eligibleOrders() == 0 ? BigDecimal.ZERO
                            : revenue.amount().divide(BigDecimal.valueOf(revenue.eligibleOrders()), 2, RoundingMode.HALF_UP),
                    "currency", "INR", "visible", true));
        }
        boolean canSeeTables = authentication.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("table:view"));
        if (canSeeTables) {
            long activeTables = dashboard.activeTables(branchId);
            metrics.put("occupancy", Map.of("value", activeTables == 0 ? BigDecimal.ZERO
                    : BigDecimal.valueOf(dashboard.occupiedTables(branchId) * 100.0 / activeTables)
                            .setScale(2, RoundingMode.HALF_UP), "unit", "PERCENT", "visible", true));
        }

        List<String> unavailable = new java.util.ArrayList<>(List.of(
                "orderCount", "activeOrders", "delayedOrders", "paymentModeSplit", "hourlySales"));
        if (!canSeeTables) unavailable.add("occupancy");
        if (authentication.getAuthorities().stream().anyMatch(a -> a.getAuthority().equals("inventory:view"))) {
            metrics.put("lowStockAlerts", Map.of("value", dashboard.lowStockItems(branchId), "visible", true));
        } else {
            unavailable.add("lowStockAlerts");
        }
        if (!revenueVisible) unavailable.add("revenue");

        return ResponseEntity.ok(Map.of(
                "branchId", branchId,
                "date", businessDate,
                "scope", "BRANCH",
                "source", "CORE_DB",
                "dateBasis", "ORDER_TIME",
                "asOf", OffsetDateTime.now(),
                "metrics", metrics,
                "unavailableMetrics", unavailable));
    }

    private boolean canSeeRevenue(User user, Authentication authentication) {
        boolean allowedRole = com.dinemaster.role.Roles.matches(user.getRole(), "OWNER")
                || com.dinemaster.role.Roles.matches(user.getRole(), "MANAGER");
        boolean permission = authentication.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("report:sales"));
        return allowedRole && permission;
    }
}
