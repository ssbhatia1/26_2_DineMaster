package com.dinemaster.restaurant.controller;

import com.dinemaster.restaurant.dto.BranchRequest;
import com.dinemaster.restaurant.dto.BranchHoursRequest;
import com.dinemaster.restaurant.entity.BranchHours;
import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.restaurant.repository.BranchHoursRepository;
import com.dinemaster.restaurant.repository.RestaurantRepository;
import com.dinemaster.security.BranchScopeService;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserBranchRepository;
import jakarta.validation.Valid;
import java.time.DateTimeException;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.EnumSet;
import java.util.Set;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/branches")
public class RestaurantController {
    private final RestaurantRepository branches;
    private final BranchScopeService branchScope;
    private final UserBranchRepository userBranches;
    private final BranchHoursRepository hours;

    public RestaurantController(RestaurantRepository branches, BranchScopeService branchScope,
            UserBranchRepository userBranches, BranchHoursRepository hours) {
        this.branches = branches;
        this.branchScope = branchScope;
        this.userBranches = userBranches;
        this.hours = hours;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('branch:view')")
    public ResponseEntity<List<Restaurant>> list(Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        if (user.getTenantId() == null) return ResponseEntity.ok(List.of());
        if (com.dinemaster.role.Roles.matches(user.getRole(), "OWNER")) {
            return ResponseEntity.ok(branches.findAllByTenantIdAndDeletedAtIsNullOrderById(user.getTenantId()));
        }
        return ResponseEntity.ok(branches.findAllByIdInAndTenantIdAndDeletedAtIsNull(
                userBranches.findBranchIds(user.getId()), user.getTenantId()));
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('branch:view')")
    public ResponseEntity<?> get(@PathVariable Long id, Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        Restaurant branch = findAccessible(id, user);
        if (branch == null) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(branch);
    }

    @PostMapping
    @PreAuthorize("hasAuthority('branch:create')")
    public ResponseEntity<?> create(@Valid @RequestBody BranchRequest request, Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        if (user.getTenantId() == null) return error(HttpStatus.FORBIDDEN, "User has no tenant");
        if (!validTimezone(request.timezone())) return error(HttpStatus.UNPROCESSABLE_ENTITY, "Invalid IANA timezone");
        if (branches.existsByTenantIdAndCodeIgnoreCaseAndDeletedAtIsNull(user.getTenantId(), request.code().trim())) {
            return error(HttpStatus.CONFLICT, "Branch code already exists in this tenant");
        }
        Restaurant branch = new Restaurant();
        apply(branch, request);
        branch.setTenantId(user.getTenantId());
        Restaurant saved = branches.save(branch);
        List<Long> assigned = new java.util.ArrayList<>(userBranches.findBranchIds(user.getId()));
        assigned.add(saved.getId());
        userBranches.replaceBranches(user.getId(), assigned);
        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('branch:update')")
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody BranchRequest request,
            @RequestHeader(value = "If-Match", required = false) Integer expectedVersion,
            Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        Restaurant branch = findAccessible(id, user);
        if (branch == null) return ResponseEntity.notFound().build();
        if (expectedVersion != null && expectedVersion != branch.getVersion()) {
            return error(HttpStatus.CONFLICT, "Branch was changed by another request");
        }
        if (!validTimezone(request.timezone())) return error(HttpStatus.UNPROCESSABLE_ENTITY, "Invalid IANA timezone");
        if (!branch.getCode().equalsIgnoreCase(request.code().trim())
                && branches.existsByTenantIdAndCodeIgnoreCaseAndDeletedAtIsNull(user.getTenantId(), request.code().trim())) {
            return error(HttpStatus.CONFLICT, "Branch code already exists in this tenant");
        }
        apply(branch, request);
        return ResponseEntity.ok(branches.save(branch));
    }

    @PostMapping("/{id}/suspend")
    @PreAuthorize("hasAuthority('branch:update')")
    public ResponseEntity<?> suspend(@PathVariable Long id, Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        Restaurant branch = findAccessible(id, user);
        if (branch == null) return ResponseEntity.notFound().build();
        branch.setActive(false);
        branches.save(branch);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{id}/hours")
    @PreAuthorize("hasAuthority('branch:view')")
    public ResponseEntity<?> getHours(@PathVariable Long id, Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        if (findAccessible(id, user) == null) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(hours.findAllByBranchIdOrderByWeekday(id));
    }

    @PutMapping("/{id}/hours")
    @Transactional
    @PreAuthorize("hasAuthority('branch:update')")
    public ResponseEntity<?> updateHours(@PathVariable Long id,
            @Valid @RequestBody List<@Valid BranchHoursRequest> requested,
            Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        Restaurant branch = findAccessible(id, user);
        if (branch == null) return ResponseEntity.notFound().build();
        if (requested == null || requested.size() != 7) {
            return error(HttpStatus.UNPROCESSABLE_ENTITY, "Provide exactly one schedule for each weekday");
        }
        Set<java.time.DayOfWeek> days = EnumSet.noneOf(java.time.DayOfWeek.class);
        for (BranchHoursRequest day : requested) {
            if (day.weekday() == null || !days.add(day.weekday())) {
                return error(HttpStatus.UNPROCESSABLE_ENTITY, "Weekdays must be unique");
            }
            if (day.closed()) {
                if (day.openTime() != null || day.closeTime() != null)
                    return error(HttpStatus.UNPROCESSABLE_ENTITY, "Closed days must not include times");
            } else if (day.openTime() == null || day.closeTime() == null
                    || !day.closeTime().isAfter(day.openTime())) {
                return error(HttpStatus.UNPROCESSABLE_ENTITY, "Hours must be a same-day interval with close after open");
            }
        }
        hours.deleteAllByBranchId(id);
        hours.saveAll(requested.stream().map(day -> new BranchHours(
                id, day.weekday(), day.openTime(), day.closeTime(), day.closed())).toList());
        return ResponseEntity.ok(hours.findAllByBranchIdOrderByWeekday(id));
    }

    private Restaurant findAccessible(Long id, User user) {
        if (user.getTenantId() == null) return null;
        if (!com.dinemaster.role.Roles.matches(user.getRole(), "OWNER")
                && !userBranches.isAssigned(user.getId(), id)) return null;
        return branches.findByIdAndTenantIdAndDeletedAtIsNull(id, user.getTenantId()).orElse(null);
    }

    private static void apply(Restaurant branch, BranchRequest request) {
        branch.setCode(request.code().trim());
        branch.setName(request.name().trim());
        branch.setAddress(request.address());
        branch.setPhone(request.phone());
        branch.setTimezone(request.timezone().trim());
    }

    private static boolean validTimezone(String timezone) {
        try { return ZoneId.getAvailableZoneIds().contains(timezone); }
        catch (DateTimeException ex) { return false; }
    }

    private static ResponseEntity<Map<String, String>> error(HttpStatus status, String message) {
        return ResponseEntity.status(status).body(Map.of("error", message));
    }
}
