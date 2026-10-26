package com.dinemaster.controller;

import com.dinemaster.dto.InventoryRequest;
import com.dinemaster.dto.StockAdjustmentRequest;
import com.dinemaster.entity.InventoryItem;
import com.dinemaster.entity.Restaurant;
import com.dinemaster.repository.InventoryRepository;
import com.dinemaster.repository.RestaurantRepository;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/inventory")
public class InventoryController {
    private final InventoryRepository inventoryRepository;
    private final RestaurantRepository restaurantRepository;

    public InventoryController(InventoryRepository inventoryRepository, RestaurantRepository restaurantRepository) {
        this.inventoryRepository = inventoryRepository;
        this.restaurantRepository = restaurantRepository;
    }

    @GetMapping
    public List<InventoryItem> list(@RequestParam Long restaurantId) {
        return inventoryRepository.findByRestaurant_IdOrderByItemNameAsc(restaurantId);
    }

    @PostMapping
    @Transactional
    public ResponseEntity<?> create(@Valid @RequestBody InventoryRequest request) {
        Restaurant restaurant = restaurantRepository.findById(request.restaurantId()).orElse(null);
        if (restaurant == null)
            return ResponseEntity.badRequest().body(Map.of("error", "Restaurant not found"));
        InventoryItem item = new InventoryItem();
        copy(request, item, restaurant);
        return ResponseEntity.status(HttpStatus.CREATED).body(inventoryRepository.save(item));
    }

    @PutMapping("/{id}")
    @Transactional
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody InventoryRequest request) {
        InventoryItem item = inventoryRepository.findById(id).orElse(null);
        if (item == null)
            return ResponseEntity.notFound().build();
        Restaurant restaurant = restaurantRepository.findById(request.restaurantId()).orElse(null);
        if (restaurant == null)
            return ResponseEntity.badRequest().body(Map.of("error", "Restaurant not found"));
        copy(request, item, restaurant);
        return ResponseEntity.ok(inventoryRepository.save(item));
    }

    @PatchMapping("/{id}/stock")
    @Transactional
    public ResponseEntity<?> adjustStock(@PathVariable Long id, @Valid @RequestBody StockAdjustmentRequest request) {
        InventoryItem item = inventoryRepository.findById(id).orElse(null);
        if (item == null)
            return ResponseEntity.notFound().build();
        BigDecimal current = item.getCurrentStock();
        BigDecimal quantity = request.quantity();
        BigDecimal updated = switch (request.mode().trim().toLowerCase()) {
            case "add" -> current.add(quantity);
            case "deduct" -> current.subtract(quantity);
            case "set" -> quantity;
            default -> null;
        };
        if (updated == null || updated.signum() < 0) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid stock adjustment"));
        }
        item.setCurrentStock(updated);
        return ResponseEntity.ok(inventoryRepository.save(item));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> delete(@PathVariable Long id) {
        if (!inventoryRepository.existsById(id))
            return ResponseEntity.notFound().build();
        inventoryRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    private void copy(InventoryRequest request, InventoryItem item, Restaurant restaurant) {
        item.setItemName(request.itemName().trim());
        item.setCurrentStock(request.currentStock());
        item.setUnit(request.unit().trim());
        item.setLowStockThreshold(request.lowStockThreshold());
        item.setExpiryDate(request.expiryDate());
        item.setRestaurant(restaurant);
    }
}