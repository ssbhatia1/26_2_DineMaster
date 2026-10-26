
package com.dinemaster.controller;

import com.dinemaster.dto.TableRequest;
import com.dinemaster.entity.DiningTable;
import com.dinemaster.entity.Restaurant;
import com.dinemaster.repository.DiningTableRepository;
import com.dinemaster.repository.RestaurantRepository;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/tables")
public class TableController {

    private final DiningTableRepository diningTableRepository;
    private final RestaurantRepository restaurantRepository;

    public TableController(
            DiningTableRepository diningTableRepository,
            RestaurantRepository restaurantRepository) {
        this.diningTableRepository = diningTableRepository;
        this.restaurantRepository = restaurantRepository;
    }

    @GetMapping
    public ResponseEntity<List<Map<String, Object>>> getAllTables(
            @RequestParam(required = false) Long restaurantId) {
        List<Map<String, Object>> response = new ArrayList<>();

        List<DiningTable> tables = restaurantId == null
                ? diningTableRepository.findAll()
                : diningTableRepository.findByRestaurant_IdOrderByTableNumberAsc(restaurantId);
        for (DiningTable table : tables) {
            response.add(toTableResponse(table));
        }

        return ResponseEntity.ok(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<?> getTableById(@PathVariable Long id) {
        return diningTableRepository.findById(id)
                .<ResponseEntity<?>>map(table -> ResponseEntity.ok(toTableResponse(table)))
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("message", "Table not found")));
    }

    @PatchMapping("/{id}/status")
    public ResponseEntity<?> updateStatus(
            @PathVariable Long id,
            @RequestParam String status) {
        if (status == null || status.isBlank() || status.length() > 30) {
            return ResponseEntity.badRequest()
                    .body(Map.of("message", "A valid table status is required"));
        }
        return diningTableRepository.findById(id)
                .<ResponseEntity<?>>map(table -> {
                    table.setStatus(status.trim());
                    return ResponseEntity.ok(toTableResponse(
                            diningTableRepository.save(table)));
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("message", "Table not found")));
    }

    @PostMapping
    public ResponseEntity<?> createTable(
            @Valid @RequestBody TableRequest request) {

        if (diningTableRepository.existsByTableNumber(
                request.getTableNumber())) {
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
    public ResponseEntity<?> updateTable(
            @PathVariable Long id,
            @Valid @RequestBody TableRequest request) {

        return diningTableRepository.findById(id)
                .<ResponseEntity<?>>map(existing -> {

                    boolean duplicate = !existing.getTableNumber().equals(
                            request.getTableNumber())
                            && diningTableRepository.existsByTableNumber(
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
    public ResponseEntity<?> deleteTable(@PathVariable Long id) {
        if (!diningTableRepository.existsById(id)) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("message", "Table not found"));
        }

        diningTableRepository.deleteById(id);
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
