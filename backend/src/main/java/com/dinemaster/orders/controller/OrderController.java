package com.dinemaster.orders.controller;





import com.dinemaster.orders.dto.CreateOrderRequest;
import com.dinemaster.orders.dto.OrderItemResponse;
import com.dinemaster.orders.dto.OrderResponse;
import com.dinemaster.orders.dto.OrderStatusRequest;
import com.dinemaster.orders.dto.PaymentRequest;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.orders.entity.OrderItem;
import com.dinemaster.orders.service.OrderService;
import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.security.BranchScopeService;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/orders")
public class OrderController {

    private final OrderService orderService;
    private final BranchScopeService branchScope;

    public OrderController(OrderService orderService, BranchScopeService branchScope) {
        this.orderService = orderService;
        this.branchScope = branchScope;
    }

    @PostMapping
    @PreAuthorize("hasAuthority('order:create')")
    public ResponseEntity<OrderResponse> createOrder(
            @Valid @RequestBody CreateOrderRequest request,
            Authentication authentication) {
        branchScope.requireBranch(authentication, request.getRestaurantId());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(orderService.createOrder(request));
    }

    @GetMapping
    @PreAuthorize("hasAuthority('order:view')")
    public ResponseEntity<List<OrderResponse>> getOrders(
            @RequestParam Long restaurantId, Authentication authentication) {
        branchScope.requireBranch(authentication, restaurantId);
        return ResponseEntity.ok(
                orderService.getOrdersByRestaurant(restaurantId));
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('order:view')")
    public ResponseEntity<OrderResponse> getOrderById(
            @PathVariable Long id, Authentication authentication) {
        branchScope.requireBranch(authentication, orderService.getOrderRestaurantId(id));
        return ResponseEntity.ok(orderService.getOrderById(id));
    }

    @GetMapping("/{id}/items")
    @PreAuthorize("hasAuthority('order:view')")
    public ResponseEntity<List<OrderItemResponse>> getOrderItems(
            @PathVariable Long id, Authentication authentication) {
        branchScope.requireBranch(authentication, orderService.getOrderRestaurantId(id));
        return ResponseEntity.ok(orderService.getOrderItems(id));
    }

    @PatchMapping("/{id}/status")
    @PreAuthorize("hasAnyAuthority('order:update','kot:update_status')")
    public ResponseEntity<OrderResponse> updateStatus(
            @PathVariable Long id,
            @Valid @RequestBody OrderStatusRequest request,
            Authentication authentication) {
        branchScope.requireBranch(authentication, orderService.getOrderRestaurantId(id));
        return ResponseEntity.ok(orderService.updateStatus(id, request));
    }

    @PostMapping("/{id}/accept-qr")
    @PreAuthorize("hasAuthority('order:update')")
    public ResponseEntity<OrderResponse> acceptQrOrder(@PathVariable Long id, Authentication authentication) {
        branchScope.requireBranch(authentication, orderService.getOrderRestaurantId(id));
        return ResponseEntity.ok(orderService.acceptQrOrder(id));
    }

    @PostMapping("/{id}/hold")
    @PreAuthorize("hasAuthority('order:park')")
    public ResponseEntity<OrderResponse> hold(@PathVariable Long id, Authentication authentication) {
        branchScope.requireBranch(authentication, orderService.getOrderRestaurantId(id));
        return ResponseEntity.ok(orderService.hold(id));
    }

    @PostMapping("/{id}/cancel")
    @PreAuthorize("hasAuthority('order:cancel')")
    public ResponseEntity<OrderResponse> cancel(@PathVariable Long id, Authentication authentication) {
        branchScope.requireBranch(authentication, orderService.getOrderRestaurantId(id));
        return ResponseEntity.ok(orderService.cancel(id));
    }

    @PostMapping("/{id}/payment")
    @PreAuthorize("hasAuthority('payment:record')")
    public ResponseEntity<OrderResponse> recordPayment(
            @PathVariable Long id,
            @Valid @RequestBody PaymentRequest request,
            Authentication authentication) {
        branchScope.requireBranch(authentication, orderService.getOrderRestaurantId(id));
        return ResponseEntity.ok(orderService.recordPayment(id, request));
    }
}
