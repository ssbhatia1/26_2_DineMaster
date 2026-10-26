
package com.dinemaster.controller;

import com.dinemaster.dto.CreateOrderRequest;
import com.dinemaster.dto.OrderItemResponse;
import com.dinemaster.dto.OrderResponse;
import com.dinemaster.dto.OrderStatusRequest;
import com.dinemaster.dto.PaymentRequest;
import com.dinemaster.service.OrderService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    @PostMapping
    public ResponseEntity<OrderResponse> createOrder(
            @Valid @RequestBody CreateOrderRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(orderService.createOrder(request));
    }

    @GetMapping
    public ResponseEntity<List<OrderResponse>> getOrders(
            @RequestParam Long restaurantId) {
        return ResponseEntity.ok(
                orderService.getOrdersByRestaurant(restaurantId));
    }

    @GetMapping("/{id}")
    public ResponseEntity<OrderResponse> getOrderById(
            @PathVariable Long id) {
        return ResponseEntity.ok(orderService.getOrderById(id));
    }

    @GetMapping("/{id}/items")
    public ResponseEntity<List<OrderItemResponse>> getOrderItems(
            @PathVariable Long id) {
        return ResponseEntity.ok(orderService.getOrderItems(id));
    }

    @PatchMapping("/{id}/status")
    public ResponseEntity<OrderResponse> updateStatus(
            @PathVariable Long id,
            @Valid @RequestBody OrderStatusRequest request) {
        return ResponseEntity.ok(orderService.updateStatus(id, request));
    }

    @PostMapping("/{id}/hold")
    public ResponseEntity<OrderResponse> hold(@PathVariable Long id) {
        return ResponseEntity.ok(orderService.hold(id));
    }

    @PostMapping("/{id}/cancel")
    public ResponseEntity<OrderResponse> cancel(@PathVariable Long id) {
        return ResponseEntity.ok(orderService.cancel(id));
    }

    @PostMapping("/{id}/payment")
    public ResponseEntity<OrderResponse> recordPayment(
            @PathVariable Long id,
            @Valid @RequestBody PaymentRequest request) {
        return ResponseEntity.ok(orderService.recordPayment(id, request));
    }
}
