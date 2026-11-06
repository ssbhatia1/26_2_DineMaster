package com.dinemaster.diningtable.controller;




import com.dinemaster.diningtable.dto.TableRequest;
import com.dinemaster.diningtable.entity.DiningTable;
import com.dinemaster.diningtable.repository.DiningTableRepository;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.restaurant.repository.RestaurantRepository;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import com.dinemaster.security.BranchScopeService;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/tables")
public class TableController {

    private final DiningTableRepository diningTableRepository;
    private final RestaurantRepository restaurantRepository;
    private final BranchScopeService branchScope;

    public TableController(
            DiningTableRepository diningTableRepository,
            RestaurantRepository restaurantRepository,
            BranchScopeService branchScope) {
        this.diningTableRepository = diningTableRepository;
        this.restaurantRepository = restaurantRepository;
        this.branchScope = branchScope;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('table:view')")
    public ResponseEntity<List<Map<String, Object>>> getAllTables(
            @RequestParam Long restaurantId, Authentication authentication) {
        branchScope.requireBranch(authentication, restaurantId);
        List<Map<String, Object>> response = new ArrayList<>();

        List<DiningTable> tables =
                diningTableRepository.findByRestaurant_IdOrderByTableNumberAsc(restaurantId);
        for (DiningTable table : tables) {
            response.add(toTableResponse(table));
        }

        return ResponseEntity.ok(response);
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('table:view')")
    public ResponseEntity<?> getTableById(@PathVariable Long id, Authentication authentication) {
        return diningTableRepository.findById(id)
                .<ResponseEntity<?>>map(table -> {
                    branchScope.requireBranch(authentication, table.getRestaurant().getId());
                    return ResponseEntity.ok(toTableResponse(table));
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("message", "Table not found")));
    }

    @PatchMapping("/{id}/status")
    @PreAuthorize("hasAuthority('table:update_status')")
    public ResponseEntity<?> updateStatus(
            @PathVariable Long id,
            @RequestParam String status, Authentication authentication) {
        if (status == null || status.isBlank() || status.length() > 30) {
            return ResponseEntity.badRequest()
                    .body(Map.of("message", "A valid table status is required"));
        }
        return diningTableRepository.findById(id)
                .<ResponseEntity<?>>map(table -> {
                    branchScope.requireBranch(authentication, table.getRestaurant().getId());
                    if (!List.of("Available", "Occupied", "Reserved", "Cleaning").contains(status.trim())) {
                        return ResponseEntity.badRequest().body(Map.of("message", "Invalid table status"));
                    }
                    table.setStatus(status.trim());
                    return ResponseEntity.ok(toTableResponse(
                            diningTableRepository.save(table)));
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("message", "Table not found")));
    }

    @PostMapping
    @PreAuthorize("hasAuthority('table:manage_layout')")
    public ResponseEntity<?> createTable(
            @Valid @RequestBody TableRequest request, Authentication authentication) {
        branchScope.requireBranch(authentication, request.getRestaurantId());

        if (diningTableRepository.existsByRestaurant_IdAndTableNumber(
                request.getRestaurantId(), request.getTableNumber())) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("message", "Table number already exists"));
        }

        DiningTable table = new DiningTable();

        ResponseEntity<?> error = copyRequest(request, table);
        if (error != null) {
            return error;
        }

        DiningTable saved = diningTableRepository.save(table);

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(toTableResponse(saved));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('table:manage_layout')")
    public ResponseEntity<?> updateTable(
            @PathVariable Long id,
            @Valid @RequestBody TableRequest request, Authentication authentication) {
        branchScope.requireBranch(authentication, request.getRestaurantId());

        return diningTableRepository.findById(id)
                .<ResponseEntity<?>>map(existing -> {

                    boolean duplicate = !existing.getTableNumber().equals(
                            request.getTableNumber())
                            && diningTableRepository.existsByRestaurant_IdAndTableNumber(
                            existing.getRestaurant().getId(), request.getTableNumber())) {
                                    request.getTableNumber());

                    if (duplicate) {
                        return ResponseEntity.status(HttpStatus.CONFLICT)
                                .body(Map.of(
                                        "message",
                                        "Table number already exists"));
                    }

                    ResponseEntity<?> error = copyRequest(request, existing);
                    if (error != null) {
                        return error;
                    }

                    DiningTable saved = diningTableRepository.save(existing);

                    return ResponseEntity.ok(toTableResponse(saved));
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("message", "Table not found")));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasAuthority('table:manage_layout')")
    public ResponseEntity<?> deleteTable(@PathVariable Long id, Authentication authentication) {
        DiningTable table = diningTableRepository.findById(id).orElse(null);
        if (table == null) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("message", "Table not found"));
        }
        branchScope.requireBranch(authentication, table.getRestaurant().getId());
        table.setActive(false);
        diningTableRepository.save(table);
        return ResponseEntity.noContent().build();
    }

    private Map<String, Object> toTableResponse(DiningTable table) {
        Map<String, Object> response = new LinkedHashMap<>();

        response.put("id", table.getId());
        response.put("table_number", table.getTableNumber());
        response.put("name", table.getName());
        response.put("capacity", table.getCapacity());
        response.put("status", table.getStatus());
        response.put("section", table.getSection());
        response.put("table_type", table.getTableType());
        response.put("is_active", table.isActive());
        response.put("is_reservable", table.isReservable());
        response.put("notes", table.getNotes());

        // Return relationship IDs, not the JPA entities themselves.
        response.put(
                "restaurant_id",
                table.getRestaurant() == null
                        ? null
                        : table.getRestaurant().getId());

        response.put(
                "waiter_id",
                table.getWaiter() == null
                        ? null
                        : table.getWaiter().getId());

        return response;
    }

    private ResponseEntity<?> copyRequest(
            TableRequest request,
            DiningTable table) {

        if (request.getRestaurantId() != null) {
            Restaurant restaurant = restaurantRepository
                    .findById(request.getRestaurantId())
                    .orElse(null);

            if (restaurant == null) {
                return ResponseEntity.badRequest()
                        .body(Map.of("message", "Restaurant not found"));
            }

            table.setRestaurant(restaurant);

        } else if (table.getRestaurant() == null) {
            return ResponseEntity.badRequest()
                    .body(Map.of(
                            "message",
                            "Restaurant ID is required for a new table"));
        }

        table.setTableNumber(request.getTableNumber());
        table.setName(request.getName());
        table.setCapacity(request.getCapacity());
        table.setStatus(request.getStatus());
        table.setSection(request.getSection());
        table.setTableType(request.getTableType());
        table.setActive(request.isActive());
        table.setReservable(request.isReservable());
        table.setNotes(request.getNotes());

        return null;
    }
}
