package com.dinemaster.inventory.controller;



import com.dinemaster.inventory.dto.InventoryRequest;
import com.dinemaster.inventory.dto.StockAdjustmentRequest;
import com.dinemaster.inventory.entity.InventoryItem;
import com.dinemaster.inventory.repository.InventoryRepository;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.restaurant.repository.RestaurantRepository;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import com.dinemaster.security.BranchScopeService;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/inventory")
public class InventoryController {
    private final InventoryRepository inventoryRepository;
    private final RestaurantRepository restaurantRepository;
    private final BranchScopeService branchScope;

    public InventoryController(InventoryRepository inventoryRepository, RestaurantRepository restaurantRepository,
            BranchScopeService branchScope) {
        this.inventoryRepository = inventoryRepository;
        this.restaurantRepository = restaurantRepository;
        this.branchScope = branchScope;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('inventory:view')")
    public List<InventoryItem> list(@RequestParam Long restaurantId, Authentication authentication) {
        branchScope.requireBranch(authentication, restaurantId);
        return inventoryRepository.findByRestaurant_IdOrderByItemNameAsc(restaurantId);
    }

    @PostMapping
    @PreAuthorize("hasAuthority('inventory:receive')")
    @Transactional
    public ResponseEntity<?> create(
            @Valid @RequestBody InventoryRequest request, Authentication authentication) {
        branchScope.requireBranch(authentication, request.restaurantId());
        Restaurant restaurant = restaurantRepository.findById(request.restaurantId()).orElse(null);
        if (restaurant == null)
            return ResponseEntity.badRequest().body(Map.of("error", "Restaurant not found"));
        InventoryItem item = new InventoryItem();
        copy(request, item, restaurant);
        return ResponseEntity.status(HttpStatus.CREATED).body(inventoryRepository.save(item));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('inventory:receive')")
    @Transactional
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody InventoryRequest request,
            Authentication authentication) {
        branchScope.requireBranch(authentication, request.restaurantId());
        InventoryItem item = inventoryRepository.findById(id).orElse(null);
        if (item == null)
            return ResponseEntity.notFound().build();
        branchScope.requireBranch(authentication, item.getRestaurantId());
        Restaurant restaurant = restaurantRepository.findById(request.restaurantId()).orElse(null);
        if (restaurant == null)
            return ResponseEntity.badRequest().body(Map.of("error", "Restaurant not found"));
        copy(request, item, restaurant);
        return ResponseEntity.ok(inventoryRepository.save(item));
    }

    @PatchMapping("/{id}/stock")
    @PreAuthorize("hasAuthority('inventory:adjust')")
    @Transactional
    public ResponseEntity<?> adjustStock(@PathVariable Long id, @Valid @RequestBody StockAdjustmentRequest request,
            Authentication authentication) {
        InventoryItem item = inventoryRepository.findById(id).orElse(null);
        if (item == null)
            return ResponseEntity.notFound().build();
        branchScope.requireBranch(authentication, item.getRestaurantId());
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
    @PreAuthorize("hasAnyRole('OWNER','MANAGER')")
    public ResponseEntity<?> delete(@PathVariable Long id, Authentication authentication) {
        InventoryItem item = inventoryRepository.findById(id).orElse(null);
        if (item == null)
            return ResponseEntity.notFound().build();
        branchScope.requireBranch(authentication, item.getRestaurantId());
        inventoryRepository.delete(item);
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
