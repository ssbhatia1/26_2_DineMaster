package com.dinemaster.qr.controller;

import com.dinemaster.qr.dto.GuestMenuResponse;
import com.dinemaster.qr.dto.GuestOrderRequest;
import com.dinemaster.qr.dto.GuestOrderResponse;
import com.dinemaster.qr.service.GuestOrderingService;
import com.dinemaster.qr.service.GuestRateLimiter;
import com.dinemaster.security.BranchScopeService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
public class GuestController {
    private final GuestOrderingService guestOrders;
    private final GuestRateLimiter rateLimiter;
    private final BranchScopeService branchScope;

    public GuestController(GuestOrderingService guestOrders, GuestRateLimiter rateLimiter,
            BranchScopeService branchScope) {
        this.guestOrders = guestOrders;
        this.rateLimiter = rateLimiter;
        this.branchScope = branchScope;
    }

    @GetMapping("/guest/menu")
    public ResponseEntity<?> menu(@RequestParam("t") String token, HttpServletRequest request) {
        if (!allow(request)) return tooManyRequests();
        GuestMenuResponse response = guestOrders.menu(token);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/guest/orders")
    public ResponseEntity<?> submit(@RequestParam("t") String token,
            @RequestHeader("Idempotency-Key") String key,
            @Valid @RequestBody GuestOrderRequest body, HttpServletRequest request) {
        if (!allow(request)) return tooManyRequests();
        GuestOrderResponse response = guestOrders.submit(token, key, body);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/guest/orders/{id}")
    public ResponseEntity<?> status(@PathVariable Long id, @RequestParam("t") String token,
            HttpServletRequest request) {
        if (!allow(request)) return tooManyRequests();
        return ResponseEntity.ok(guestOrders.status(token, id));
    }

    @PostMapping("/guest/call-waiter")
    public ResponseEntity<?> callWaiter(@RequestParam("t") String token, HttpServletRequest request) {
        if (!allow(request)) return tooManyRequests();
        boolean created = guestOrders.callWaiter(token);
        return ResponseEntity.accepted().body(Map.of("accepted", true,
                "message", created ? "Waiter has been notified" : "A waiter request is already pending"));
    }

    @GetMapping("/api/v1/guest-service-requests")
    @PreAuthorize("hasAuthority('table:view')")
    public List<Map<String, Object>> pendingCalls(@RequestParam Long branchId, Authentication authentication) {
        branchScope.requireBranch(authentication, branchId);
        return guestOrders.pendingCalls(branchId);
    }

    @PostMapping("/api/v1/guest-service-requests/{id}/acknowledge")
    @PreAuthorize("hasAuthority('table:update_status')")
    public ResponseEntity<Void> acknowledge(@PathVariable Long id, Authentication authentication) {
        Long branchId = guestOrders.getCallBranchId(id);
        branchScope.requireBranch(authentication, branchId);
        guestOrders.acknowledgeCall(id, branchId);
        return ResponseEntity.noContent().build();
    }

    private boolean allow(HttpServletRequest request) {
        return rateLimiter.allow(request.getRemoteAddr() == null ? "unknown" : request.getRemoteAddr());
    }

    private ResponseEntity<Map<String, String>> tooManyRequests() {
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .body(Map.of("error", "Guest request limit exceeded. Please try again shortly."));
    }
}
