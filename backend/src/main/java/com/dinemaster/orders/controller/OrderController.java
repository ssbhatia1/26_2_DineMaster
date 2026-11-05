package com.dinemaster.orders.controller;
import com.dinemaster.orders.dto.AddOrderItemsRequest;
import com.dinemaster.orders.dto.CreateOrderRequest;
import com.dinemaster.orders.dto.OrderItemResponse;
import com.dinemaster.orders.dto.OrderResponse;
import com.dinemaster.orders.dto.OrderStatusRequest;
import com.dinemaster.orders.dto.PaymentRequest;
import com.dinemaster.orders.service.OrderService;


import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.access.prepost.PreAuthorize;

import java.util.List;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('WAITER','CASHIER','MANAGER','OWNER')")
    public ResponseEntity<OrderResponse> createOrder(
            @Valid @RequestBody CreateOrderRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(orderService.createOrder(request));
    }

    @GetMapping
    @PreAuthorize("hasAnyRole('WAITER','CASHIER','CHEF','MANAGER','OWNER')")
    public ResponseEntity<List<OrderResponse>> getOrders(
            @RequestParam Long restaurantId) {
        return ResponseEntity.ok(
                orderService.getOrdersByRestaurant(restaurantId));
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('WAITER','CASHIER','CHEF','MANAGER','OWNER')")
    public ResponseEntity<OrderResponse> getOrderById(
            @PathVariable Long id) {
        return ResponseEntity.ok(orderService.getOrderById(id));
    }

    @GetMapping("/{id}/items")
    @PreAuthorize("hasAnyRole('WAITER','CASHIER','CHEF','MANAGER','OWNER')")
    public ResponseEntity<List<OrderItemResponse>> getOrderItems(
            @PathVariable Long id) {
        return ResponseEntity.ok(orderService.getOrderItems(id));
    }

    @PostMapping("/{id}/items")
    @PreAuthorize("hasAnyRole('WAITER','CASHIER','MANAGER','OWNER')")
    public ResponseEntity<OrderResponse> addItems(
            @PathVariable Long id,
            @Valid @RequestBody AddOrderItemsRequest request) {
        return ResponseEntity.ok(orderService.addItems(id, request));
    }

    @PatchMapping("/{id}/status")
    @PreAuthorize("hasAnyRole('CHEF','MANAGER','OWNER')")
    public ResponseEntity<OrderResponse> updateStatus(
            @PathVariable Long id,
            @Valid @RequestBody OrderStatusRequest request) {
        return ResponseEntity.ok(orderService.updateStatus(id, request));
    }

    @PostMapping("/{id}/hold")
    @PreAuthorize("hasAnyRole('WAITER','MANAGER','OWNER')")
    public ResponseEntity<OrderResponse> hold(@PathVariable Long id) {
        return ResponseEntity.ok(orderService.hold(id));
    }

    @PostMapping("/{id}/cancel")
    @PreAuthorize("hasAnyRole('WAITER','MANAGER','OWNER')")
    public ResponseEntity<OrderResponse> cancel(@PathVariable Long id) {
        return ResponseEntity.ok(orderService.cancel(id));
    }

    @PostMapping("/{id}/payment")
    @PreAuthorize("hasAnyRole('CASHIER','MANAGER','OWNER')")
    public ResponseEntity<OrderResponse> recordPayment(
            @PathVariable Long id,
            @Valid @RequestBody PaymentRequest request) {
        return ResponseEntity.ok(orderService.recordPayment(id, request));
    }
}
