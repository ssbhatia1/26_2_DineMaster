package com.dinemaster.diningtable.controller;

import com.dinemaster.diningtable.dto.TableRequest;
import com.dinemaster.diningtable.dto.TableStatusRequest;
import com.dinemaster.diningtable.dto.WaiterAssignmentRequest;
import com.dinemaster.diningtable.entity.DiningTable;
import com.dinemaster.diningtable.repository.DiningTableRepository;
import com.dinemaster.diningtable.repository.FloorRepository;
import com.dinemaster.orders.repository.OrderRepository;
import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.restaurant.repository.RestaurantRepository;
import com.dinemaster.security.BranchScopeService;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserBranchRepository;
import com.dinemaster.user.repository.UserRepository;
import jakarta.validation.Valid;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.transaction.annotation.Transactional;

@RestController
@RequestMapping("/api/v1/tables")
public class TableController {
    private static final Map<String, Set<String>> TRANSITIONS = Map.of(
            "AVAILABLE", Set.of("RESERVED", "OCCUPIED", "OUT_OF_SERVICE"),
            "RESERVED", Set.of("AVAILABLE", "OCCUPIED"),
            "OCCUPIED", Set.of("ORDERING", "CLEANING"),
            "ORDERING", Set.of("FOOD_PENDING", "CLEANING"),
            "FOOD_PENDING", Set.of("PREPARING", "CLEANING"),
            "PREPARING", Set.of("SERVED", "CLEANING"),
            "SERVED", Set.of("BILL_REQUESTED", "CLEANING"),
            "BILL_REQUESTED", Set.of("CLEANING"),
            "CLEANING", Set.of("AVAILABLE"),
            "OUT_OF_SERVICE", Set.of("AVAILABLE"));

    private final DiningTableRepository tables;
    private final RestaurantRepository branches;
    private final FloorRepository floors;
    private final OrderRepository orders;
    private final UserRepository users;
    private final UserBranchRepository userBranches;
    private final BranchScopeService branchScope;

    public TableController(DiningTableRepository tables, RestaurantRepository branches, FloorRepository floors,
            OrderRepository orders, UserRepository users, UserBranchRepository userBranches,
            BranchScopeService branchScope) {
        this.tables = tables;
        this.branches = branches;
        this.floors = floors;
        this.orders = orders;
        this.users = users;
        this.userBranches = userBranches;
        this.branchScope = branchScope;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('table:view')")
    public ResponseEntity<?> list(@RequestParam(required = false) Long branchId,
            @RequestParam(required = false) Long restaurantId,
            @RequestParam(required = false) Long floorId,
            @RequestParam(required = false) String status, Authentication authentication) {
        Long selectedBranch = resolveBranch(branchId, restaurantId);
        if (selectedBranch == null) return error(HttpStatus.BAD_REQUEST, "branchId is required");
        branchScope.requireBranch(authentication, selectedBranch);
        if (floorId != null && floors.findByIdAndBranchId(floorId, selectedBranch).isEmpty()) {
            return ResponseEntity.ok(List.of());
        }
        List<DiningTable> result = floorId != null
                ? tables.findAllByRestaurant_IdAndFloorIdAndActiveTrueOrderByTableNumberAsc(selectedBranch, floorId)
                : tables.findAllByRestaurant_IdAndActiveTrueOrderByTableNumberAsc(selectedBranch);
        if (status != null && !status.isBlank()) {
            String requestedStatus = normalizeStatus(status);
            result = result.stream().filter(table -> normalizeStatus(table.getStatus()).equals(requestedStatus)).toList();
        }
        return ResponseEntity.ok(result.stream().map(this::toResponse).toList());
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('table:view')")
    public ResponseEntity<?> get(@PathVariable Long id, Authentication authentication) {
        DiningTable table = tables.findById(id).orElse(null);
        if (table == null || table.getRestaurant() == null) return ResponseEntity.notFound().build();
        branchScope.requireBranch(authentication, table.getRestaurant().getId());
        return ResponseEntity.ok(toResponse(table));
    }

    @PostMapping
    @PreAuthorize("hasAuthority('table:manage_layout')")
    public ResponseEntity<?> create(@Valid @RequestBody TableRequest request, Authentication authentication) {
        Long branchId = request.getRestaurantId();
        if (branchId == null) return error(HttpStatus.BAD_REQUEST, "restaurantId is required");
        branchScope.requireBranch(authentication, branchId);
        if (tables.existsByRestaurant_IdAndTableNumber(branchId, request.getTableNumber())) {
            return error(HttpStatus.CONFLICT, "Table label already exists in this branch");
        }
        DiningTable table = new DiningTable();
        ResponseEntity<?> invalid = applyLayout(request, table, branchId);
        if (invalid != null) return invalid;
        table.setStatus("Available");
        return ResponseEntity.status(HttpStatus.CREATED).body(toResponse(tables.save(table)));
    }

    @PutMapping("/{id}")
    @Transactional
    @PreAuthorize("hasAuthority('table:manage_layout')")
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody TableRequest request,
            @RequestParam(required = false) Integer version, Authentication authentication) {
        Long branchId = request.getRestaurantId();
        if (branchId == null) return error(HttpStatus.BAD_REQUEST, "restaurantId is required");
        branchScope.requireBranch(authentication, branchId);
        DiningTable table = tables.findForUpdateById(id).filter(t -> t.getRestaurant() != null
                && t.getRestaurant().getId().equals(branchId)).orElse(null);
        if (table == null) return ResponseEntity.notFound().build();
        if (version != null && version != table.getVersion()) return error(HttpStatus.CONFLICT, "Table layout is stale");
        if (orders.countOpenOrdersForTable(id) > 0) return error(HttpStatus.CONFLICT, "Table layout cannot change while an order is open");
        if (!table.getTableNumber().equalsIgnoreCase(request.getTableNumber())
                && tables.existsByRestaurant_IdAndTableNumber(branchId, request.getTableNumber())) {
            return error(HttpStatus.CONFLICT, "Table label already exists in this branch");
        }
        ResponseEntity<?> invalid = applyLayout(request, table, branchId);
        if (invalid != null) return invalid;
        try { return ResponseEntity.ok(toResponse(tables.save(table))); }
        catch (OptimisticLockingFailureException ex) { return error(HttpStatus.CONFLICT, "Table layout changed concurrently"); }
    }

    @PutMapping("/{id}/status")
    @PreAuthorize("hasAuthority('table:update_status')")
    public ResponseEntity<?> updateStatus(@PathVariable Long id, @Valid @RequestBody TableStatusRequest request,
            Authentication authentication) {
        return changeStatus(id, request.status(), request.version(), authentication);
    }

    // Backward-compatible route for existing clients; new clients should use PUT with a version.
    @PatchMapping("/{id}/status")
    @PreAuthorize("hasAuthority('table:update_status')")
    public ResponseEntity<?> updateStatusLegacy(@PathVariable Long id, @RequestParam String status,
            Authentication authentication) {
        return changeStatus(id, status, null, authentication);
    }

    @PutMapping("/{id}/waiter")
    @PreAuthorize("hasAuthority('table:assign_waiter')")
    public ResponseEntity<?> assignWaiter(@PathVariable Long id, @Valid @RequestBody WaiterAssignmentRequest request,
            Authentication authentication) {
        DiningTable table = tables.findById(id).orElse(null);
        if (table == null || table.getRestaurant() == null) return ResponseEntity.notFound().build();
        Long branchId = table.getRestaurant().getId();
        branchScope.requireBranch(authentication, branchId);
        User actor = branchScope.requireUser(authentication);
        if (request.waiterId() == null) {
            table.setWaiter(null);
        } else {
            User waiter = users.findById(request.waiterId()).filter(User::isActive).orElse(null);
            if (waiter == null || !java.util.Objects.equals(waiter.getTenantId(), actor.getTenantId())
                    || !com.dinemaster.role.Roles.matches(waiter.getRole(), "WAITER")
                    || !userBranches.isAssigned(waiter.getId(), branchId)) {
                return error(HttpStatus.UNPROCESSABLE_ENTITY, "Waiter must be active and assigned to this branch");
            }
            table.setWaiter(waiter);
        }
        try { return ResponseEntity.ok(toResponse(tables.save(table))); }
        catch (OptimisticLockingFailureException ex) { return error(HttpStatus.CONFLICT, "Table changed concurrently"); }
    }

    @DeleteMapping("/{id}")
    @Transactional
    @PreAuthorize("hasAuthority('table:manage_layout')")
    public ResponseEntity<?> deactivate(@PathVariable Long id, Authentication authentication) {
        DiningTable table = tables.findForUpdateById(id).orElse(null);
        if (table == null || table.getRestaurant() == null) return ResponseEntity.notFound().build();
        branchScope.requireBranch(authentication, table.getRestaurant().getId());
        if (orders.countOpenOrdersForTable(id) > 0) return error(HttpStatus.CONFLICT, "Table cannot be deactivated while an order is open");
        table.setActive(false);
        try { tables.save(table); return ResponseEntity.noContent().build(); }
        catch (OptimisticLockingFailureException ex) { return error(HttpStatus.CONFLICT, "Table changed concurrently"); }
    }

    private ResponseEntity<?> changeStatus(Long id, String rawStatus, Integer version, Authentication authentication) {
        DiningTable table = tables.findById(id).orElse(null);
        if (table == null || table.getRestaurant() == null) return ResponseEntity.notFound().build();
        branchScope.requireBranch(authentication, table.getRestaurant().getId());
        User actor = branchScope.requireUser(authentication);
        if (com.dinemaster.role.Roles.matches(actor.getRole(), "WAITER")
                && (table.getWaiter() == null || !table.getWaiter().getId().equals(actor.getId()))) {
            return error(HttpStatus.FORBIDDEN, "Waiters may update only tables assigned to them");
        }
        if (rawStatus == null || rawStatus.isBlank()) return error(HttpStatus.BAD_REQUEST, "status is required");
        if (version != null && version != table.getVersion()) return error(HttpStatus.CONFLICT, "Table status is stale");
        String current = normalizeStatus(table.getStatus());
        String next = normalizeStatus(rawStatus);
        if (current.equals(next)) return ResponseEntity.ok(toResponse(table));
        if (!TRANSITIONS.getOrDefault(current, Set.of()).contains(next)) {
            return error(HttpStatus.CONFLICT, "Illegal table status transition");
        }
        table.setStatus(next);
        try { return ResponseEntity.ok(toResponse(tables.save(table))); }
        catch (OptimisticLockingFailureException ex) { return error(HttpStatus.CONFLICT, "Table status changed concurrently"); }
    }

    private ResponseEntity<?> applyLayout(TableRequest request, DiningTable table, Long branchId) {
        Restaurant branch = branches.findById(branchId).orElse(null);
        if (branch == null) return ResponseEntity.notFound().build();
        if (request.getFloorId() != null && floors.findByIdAndBranchId(request.getFloorId(), branchId).isEmpty()) {
            return error(HttpStatus.UNPROCESSABLE_ENTITY, "Floor must belong to this branch");
        }
        table.setRestaurant(branch);
        table.setFloorId(request.getFloorId());
        table.setTableNumber(request.getTableNumber().trim());
        table.setName(request.getName());
        table.setCapacity(request.getCapacity());
        table.setSection(request.getSection());
        table.setTableType(request.getTableType());
        table.setActive(request.isActive());
        table.setReservable(request.isReservable());
        table.setNotes(request.getNotes());
        table.setPositionX(request.getPositionX());
        table.setPositionY(request.getPositionY());
        return null;
    }

    private Map<String, Object> toResponse(DiningTable table) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("id", table.getId());
        result.put("tableNumber", table.getTableNumber());
        result.put("table_number", table.getTableNumber());
        result.put("name", table.getName());
        result.put("capacity", table.getCapacity());
        result.put("status", table.getStatus());
        result.put("statusCode", normalizeStatus(table.getStatus()));
        result.put("section", table.getSection());
        result.put("tableType", table.getTableType());
        result.put("table_type", table.getTableType());
        result.put("active", table.isActive());
        result.put("is_active", table.isActive());
        result.put("reservable", table.isReservable());
        result.put("is_reservable", table.isReservable());
        result.put("floorId", table.getFloorId());
        result.put("positionX", table.getPositionX());
        result.put("positionY", table.getPositionY());
        result.put("waiterId", table.getWaiter() == null ? null : table.getWaiter().getId());
        result.put("waiter_id", table.getWaiter() == null ? null : table.getWaiter().getId());
        result.put("version", table.getVersion());
        result.put("branchId", table.getRestaurant() == null ? null : table.getRestaurant().getId());
        result.put("restaurant_id", table.getRestaurant() == null ? null : table.getRestaurant().getId());
        return result;
    }

    private static Long resolveBranch(Long branchId, Long restaurantId) {
        if (branchId != null && restaurantId != null && !branchId.equals(restaurantId)) return null;
        return branchId == null ? restaurantId : branchId;
    }

    private static String normalizeStatus(String status) {
        String normalized = status.trim().toUpperCase(java.util.Locale.ROOT).replace(' ', '_');
        return switch (normalized) {
            case "FREE" -> "AVAILABLE";
            case "OCCUPIED" -> "OCCUPIED";
            case "PENDING" -> "FOOD_PENDING";
            default -> normalized;
        };
    }

    private static ResponseEntity<Map<String, String>> error(HttpStatus status, String message) {
        return ResponseEntity.status(status).body(Map.of("error", message));
    }
}
