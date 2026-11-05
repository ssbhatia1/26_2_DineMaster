package com.dinemaster.kitchen.controller;
import com.dinemaster.kitchen.dto.CreateKotRequest;
import com.dinemaster.kitchen.entity.Kot;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.orders.entity.OrderItem;
import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.user.entity.User;
import com.dinemaster.kitchen.repository.KotRepository;
import com.dinemaster.orders.repository.OrderItemRepository;
import com.dinemaster.orders.repository.OrderRepository;
import com.dinemaster.user.repository.UserRepository;
import com.dinemaster.role.Roles;


import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.access.prepost.PreAuthorize;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/kot")
public class KotController {
    private static final List<String> STATUSES = List.of("Pending", "Cooking", "Ready", "Served", "Cancelled");
    private final KotRepository kotRepository;
    private final OrderRepository orderRepository;
    private final OrderItemRepository orderItemRepository;
    private final UserRepository userRepository;

    public KotController(KotRepository kotRepository, OrderRepository orderRepository,
            OrderItemRepository orderItemRepository, UserRepository userRepository) {
        this.kotRepository = kotRepository;
        this.orderRepository = orderRepository;
        this.orderItemRepository = orderItemRepository;
        this.userRepository = userRepository;
    }

    @GetMapping
    @PreAuthorize("hasAnyRole('WAITER','CHEF','MANAGER','OWNER')")
    public List<Map<String, Object>> listByRestaurant(@RequestParam Long restaurantId) {
        return kotRepository.findByOrder_Restaurant_IdOrderByCreatedAtDesc(restaurantId)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    @GetMapping("/order/{orderId}")
    @PreAuthorize("hasAnyRole('WAITER','CHEF','MANAGER','OWNER')")
    public List<Map<String, Object>> list(@PathVariable Long orderId) {
        return kotRepository.findByOrder_IdOrderByCreatedAtAsc(orderId)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('WAITER','MANAGER','OWNER')")
    @Transactional
    public ResponseEntity<?> create(@Valid @RequestBody CreateKotRequest request) {
        return orderRepository.findById(request.orderId()).map(order -> {
            var existing = kotRepository.findFirstByOrder_IdOrderByCreatedAtDesc(order.getId());
            var pendingItems = orderItemRepository.findByOrder_Id(order.getId()).stream()
                    .filter(item -> item.getKot() == null)
                    .toList();
            if (existing.isPresent() && pendingItems.isEmpty()
                    && !"Cancelled".equals(existing.get().getStatus())) {
                return ResponseEntity.ok(toResponse(existing.get()));
            }
            Kot kot = new Kot();
            kot.setOrder(order);
            if (request.chefId() != null) {
                User chef = userRepository.findById(request.chefId())
                        .orElseThrow(() -> new org.springframework.web.server.ResponseStatusException(
                                HttpStatus.NOT_FOUND, "Chef not found"));
                if (!chef.isActive() || !Roles.canonical(chef.getRole()).equals("CHEF")
                        || chef.getRestaurant() == null || order.getRestaurant() == null
                        || !order.getRestaurant().getId().equals(chef.getRestaurant().getId())) {
                    throw new org.springframework.web.server.ResponseStatusException(
                            HttpStatus.BAD_REQUEST, "Chef does not belong to this restaurant");
                }
                kot.setChefName(chef.getName());
            }
            kot.setKotNumber(request.kotNumber() == null || request.kotNumber().isBlank()
                    ? "KOT-" + System.currentTimeMillis()
                    : request.kotNumber().trim());
            kot.setPriority(
                    request.priority() == null || request.priority().isBlank() ? "Normal" : request.priority().trim());
            if (request.estimatedTime() != null)
                kot.setEstimatedTime(request.estimatedTime());
            Kot saved = kotRepository.save(kot);
            pendingItems.stream()
                    .forEach(item -> {
                        item.setKot(saved);
                        item.setStatus("Sent to Kitchen");
                    });
            orderItemRepository.saveAll(pendingItems);
            order.setStatus("Received");
            orderRepository.save(order);
            return ResponseEntity.status(HttpStatus.CREATED).body(toResponse(saved));
        }).orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PatchMapping("/{id}/status")
    @PreAuthorize("hasAnyRole('CHEF','MANAGER','OWNER')")
    @Transactional
    public ResponseEntity<?> updateStatus(@PathVariable Long id, @RequestParam String value) {
        if (value == null || !STATUSES.contains(value)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid KOT status"));
        }
        return kotRepository.findById(id).map(kot -> {
            kot.setStatus(value);
            OffsetDateTime now = OffsetDateTime.now();
            if ("Cooking".equals(value))
                kot.setStartedCookingAt(now);
            if ("Ready".equals(value))
                kot.setReadyAt(now);
            if ("Served".equals(value))
                kot.setServedAt(now);
            return ResponseEntity.ok(toResponse(kotRepository.save(kot)));
        }).orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PostMapping("/{kotId}/items/{itemId}")
    @PreAuthorize("hasAnyRole('CHEF','MANAGER','OWNER')")
    @Transactional
    public ResponseEntity<?> assignItem(@PathVariable Long kotId, @PathVariable Long itemId) {
        Kot kot = kotRepository.findById(kotId).orElse(null);
        OrderItem item = orderItemRepository.findById(itemId).orElse(null);
        if (kot == null || item == null)
            return ResponseEntity.notFound().build();
        if (!kot.getOrder().getId().equals(item.getOrder().getId())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Item belongs to another order"));
        }
        item.setKot(kot);
        return ResponseEntity.ok(orderItemRepository.save(item));
    }

    @DeleteMapping("/{kotId}/items/{itemId}")
    @PreAuthorize("hasAnyRole('CHEF','MANAGER','OWNER')")
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