package com.dinemaster.controller;

import com.dinemaster.dto.CreateKotRequest;
import com.dinemaster.entity.Kot;
import com.dinemaster.repository.KotRepository;
import com.dinemaster.repository.OrderRepository;
import com.dinemaster.repository.OrderItemRepository;
import com.dinemaster.entity.OrderItem;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
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

    public KotController(KotRepository kotRepository, OrderRepository orderRepository,
            OrderItemRepository orderItemRepository) {
        this.kotRepository = kotRepository;
        this.orderRepository = orderRepository;
        this.orderItemRepository = orderItemRepository;
    }

    @GetMapping
    public List<Map<String, Object>> listByRestaurant(@RequestParam Long restaurantId) {
        return kotRepository.findByOrder_Restaurant_IdOrderByCreatedAtDesc(restaurantId)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    @GetMapping("/order/{orderId}")
    public List<Map<String, Object>> list(@PathVariable Long orderId) {
        return kotRepository.findByOrder_IdOrderByCreatedAtAsc(orderId)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    @PostMapping
    @Transactional
    public ResponseEntity<?> create(@Valid @RequestBody CreateKotRequest request) {
        return orderRepository.findById(request.orderId()).map(order -> {
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