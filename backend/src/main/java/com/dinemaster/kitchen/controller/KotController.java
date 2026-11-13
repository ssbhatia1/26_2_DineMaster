package com.dinemaster.kitchen.controller;



import com.dinemaster.kitchen.dto.CreateKotRequest;
import com.dinemaster.kitchen.entity.Kot;
import com.dinemaster.kitchen.repository.KotRepository;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.orders.entity.OrderItem;
import com.dinemaster.orders.repository.OrderItemRepository;
import com.dinemaster.orders.repository.OrderRepository;
import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.security.BranchScopeService;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.context.annotation.Lazy;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/kitchen-tickets")
public class KotController {
    private static final List<String> STATUSES = List.of(
            "Pending", "Cooking", "Preparing", "Ready", "Served", "Completed", "Cancelled");
    private final KotRepository kotRepository;
    private final OrderRepository orderRepository;
    private final OrderItemRepository orderItemRepository;
    private final BranchScopeService branchScope;

    public KotController(KotRepository kotRepository, OrderRepository orderRepository,
            OrderItemRepository orderItemRepository, @Lazy BranchScopeService branchScope) {
        this.kotRepository = kotRepository;
        this.orderRepository = orderRepository;
        this.orderItemRepository = orderItemRepository;
        this.branchScope = branchScope;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('kot:view')")
    public List<Map<String, Object>> listByRestaurant(@RequestParam Long restaurantId,
            Authentication authentication) {
        branchScope.requireBranch(authentication, restaurantId);
        return kotRepository.findByOrder_Restaurant_IdOrderByCreatedAtDesc(restaurantId)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    @GetMapping("/order/{orderId}")
    @PreAuthorize("hasAuthority('kot:view')")
    public List<Map<String, Object>> list(@PathVariable Long orderId,
            Authentication authentication) {
        Order order = orderRepository.findById(orderId).orElseThrow();
        branchScope.requireBranch(authentication, order.getRestaurant().getId());
        return kotRepository.findByOrder_IdOrderByCreatedAtAsc(orderId)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    @PostMapping
    @PreAuthorize("hasAuthority('order:create')")
    @Transactional
    public ResponseEntity<?> create(@Valid @RequestBody CreateKotRequest request,
            Authentication authentication) {
        return orderRepository.findById(request.orderId()).map(order -> {
            branchScope.requireBranch(authentication, order.getRestaurant().getId());
            if ("DRAFT".equalsIgnoreCase(order.getStatus())) {
                return ResponseEntity.status(HttpStatus.CONFLICT)
                        .body(Map.of("error", "QR draft orders must be accepted before kitchen processing"));
            }
            if (request.kotNumber() == null || request.kotNumber().isBlank()) {
                var existing = kotRepository.findByOrder_IdOrderByCreatedAtAsc(order.getId())
                        .stream()
                        .filter(kot -> "Pending".equals(kot.getStatus())
                                || "Cooking".equals(kot.getStatus()))
                        .findFirst();
                if (existing.isPresent()) {
                    return ResponseEntity.ok(toResponse(existing.get()));
                }
            }
            Kot kot = new Kot();
            kot.setOrder(order);
            kot.setKotNumber(request.kotNumber() == null || request.kotNumber().isBlank()
                    ? "KOT-" + System.currentTimeMillis()
                    : request.kotNumber().trim());
            kot.setPriority(
                    request.priority() == null || request.priority().isBlank() ? "Normal" : request.priority().trim());
            if (request.estimatedTime() != null)
                kot.setEstimatedTime(request.estimatedTime());
            return ResponseEntity.status(HttpStatus.CREATED).body(toResponse(kotRepository.save(kot)));
        }).orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PatchMapping("/{id}/status")
    @PreAuthorize("hasAuthority('kot:update_status')")
    @Transactional
    public ResponseEntity<?> updateStatus(@PathVariable Long id, @RequestParam String value,
            Authentication authentication) {
        if (value == null || !STATUSES.contains(value)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid KOT status"));
        }
        final String normalizedValue = "Preparing".equals(value) ? "Cooking"
                : "Completed".equals(value) ? "Served" : value;
        return kotRepository.findById(id).map(kot -> {
            branchScope.requireBranch(authentication, kot.getOrder().getRestaurant().getId());
            String current = kot.getStatus();
            boolean waiter = hasRole(authentication, "WAITER");
            boolean chef = hasRole(authentication, "CHEF");
            boolean manager = hasRole(authentication, "MANAGER") || hasRole(authentication, "OWNER");
            boolean allowedTransition = switch (current) {
                case "Pending" -> normalizedValue.equals("Cooking") || (manager && normalizedValue.equals("Cancelled"));
                case "Cooking" -> normalizedValue.equals("Ready") || (manager && normalizedValue.equals("Cancelled"));
                case "Ready" -> normalizedValue.equals("Served") || (manager && normalizedValue.equals("Cancelled"));
                default -> false;
            };
            boolean allowedByRole = waiter
                    ? current.equals("Ready") && normalizedValue.equals("Served")
                    : chef
                    ? (current.equals("Pending") && normalizedValue.equals("Cooking"))
                            || (current.equals("Cooking") && normalizedValue.equals("Ready"))
                            : manager;
            if (!allowedTransition || !allowedByRole) {
                return ResponseEntity.status(409).body(Map.of("error", "Invalid or unauthorized KOT transition"));
            }
            kot.setStatus(normalizedValue);
            OffsetDateTime now = OffsetDateTime.now();
            if ("Cooking".equals(normalizedValue))
                kot.setStartedCookingAt(now);
            if ("Ready".equals(normalizedValue))
                kot.setReadyAt(now);
            if ("Served".equals(normalizedValue))
                kot.setServedAt(now);
            updateOrderStatus(kot.getOrder());
            return ResponseEntity.ok(toResponse(kotRepository.save(kot)));
        }).orElseGet(() -> ResponseEntity.notFound().build());
    }

    private void updateOrderStatus(Order order) {
        List<String> statuses = kotRepository.findByOrder_IdOrderByCreatedAtAsc(order.getId())
                .stream().map(Kot::getStatus).toList();
        if (statuses.isEmpty()) return;
        String orderStatus = statuses.stream().allMatch("Served"::equals) ? "Served"
                : statuses.stream().allMatch(status -> "Ready".equals(status) || "Served".equals(status))
                        ? "Ready"
                        : statuses.stream().anyMatch(status -> "Cooking".equals(status))
                                ? "Preparing" : "Sent to Kitchen";
        order.setStatus(orderStatus);
    }

    private boolean hasRole(Authentication authentication, String role) {
        return authentication.getAuthorities().stream()
                .anyMatch(authority -> authority.getAuthority().equals("ROLE_" + role));
    }

    @PostMapping("/{kotId}/items/{itemId}")
    @PreAuthorize("hasAuthority('kot:update_status')")
    @Transactional
    public ResponseEntity<?> assignItem(@PathVariable Long kotId, @PathVariable Long itemId,
            Authentication authentication) {
        Kot kot = kotRepository.findById(kotId).orElse(null);
        OrderItem item = orderItemRepository.findById(itemId).orElse(null);
        if (kot == null || item == null)
            return ResponseEntity.notFound().build();
        branchScope.requireBranch(authentication, kot.getOrder().getRestaurant().getId());
        if (!kot.getOrder().getId().equals(item.getOrder().getId())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Item belongs to another order"));
        }
        int updated = orderItemRepository.assignToKot(item.getId(), kot.getOrder().getId(), kot.getId());
        if (updated == 0) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(Map.of(
                "itemId", item.getId(),
                "kotId", kot.getId(),
                "orderId", kot.getOrder().getId(),
                "productId", item.getProduct().getId(),
                "status", item.getStatus()));
    }

    @DeleteMapping("/{kotId}/items/{itemId}")
    @PreAuthorize("hasAuthority('kot:update_status')")
    @Transactional
    public ResponseEntity<?> unassignItem(@PathVariable Long kotId, @PathVariable Long itemId) {
        OrderItem item = orderItemRepository.findById(itemId).orElse(null);
        if (item == null || item.getKot() == null || !item.getKot().getId().equals(kotId)) {
            return ResponseEntity.notFound().build();
        }
        item.setKot(null);
        orderItemRepository.save(item);
        return ResponseEntity.noContent().build();
    }

    private Map<String, Object> toResponse(Kot kot) {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("id", kot.getId());
        response.put("orderId", kot.getOrder() == null ? null : kot.getOrder().getId());
        response.put("kotNumber", kot.getKotNumber());
        response.put("status", kot.getStatus());
        response.put("createdAt", kot.getCreatedAt());
        response.put("startedCookingAt", kot.getStartedCookingAt());
        response.put("readyAt", kot.getReadyAt());
        response.put("servedAt", kot.getServedAt());
        response.put("delayReason", kot.getDelayReason());
        response.put("chefName", kot.getChefName());
        response.put("priority", kot.getPriority());
        response.put("estimatedTime", kot.getEstimatedTime());
        return response;
    }
}
