package com.dinemaster.security;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpInputMessage;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.RequestBodyAdviceAdapter;
import java.lang.reflect.Method;
import java.lang.reflect.Type;

@ControllerAdvice
public class BranchScopeBodyAdvice extends RequestBodyAdviceAdapter {
    private final BranchScopeService scope;
    private final HttpServletRequest request;

    public BranchScopeBodyAdvice(BranchScopeService scope, HttpServletRequest request) {
        this.scope = scope; this.request = request;
    }

    @Override
    public boolean supports(MethodParameter parameter, Type targetType,
            Class<? extends HttpMessageConverter<?>> converterType) {
        return true;
    }

    @Override
    public Object afterBodyRead(Object body, HttpInputMessage inputMessage, MethodParameter parameter,
            Type targetType, Class<? extends HttpMessageConverter<?>> converterType) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) return body;
        String path = request.getRequestURI();
        if (!path.startsWith("/api/v1/") || path.startsWith("/api/v1/auth/")) return body;

        Long branchId = readNumber(body, "getRestaurantId", "restaurantId", "getBranchId", "branchId");
        if (branchId == null && path.startsWith("/api/v1/recipes")) {
            Long productId = readNumber(body, "getProductId", "productId");
            branchId = scope.branchForProduct(productId);
        }
        if (branchId == null && path.equals("/api/v1/kitchen-tickets")) {
            Long orderId = readNumber(body, "getOrderId", "orderId");
            if (orderId != null) branchId = scope.branchForResource("/api/v1/orders/" + orderId, orderId);
        }
        if (branchId == null && requiresBranch(path)) {
            String[] segments = path.split("/");
            if (segments.length > 4 && segments[4].matches("\\d+")) {
                branchId = scope.branchForResource(path, Long.valueOf(segments[4]));
            }
        }
        if (requiresBranch(path) && branchId == null) {
            throw new IllegalArgumentException("restaurantId or a branch-owned resource ID is required");
        }
        if (branchId != null) scope.requireBranch(authentication, branchId);
        return body;
    }

    private boolean requiresBranch(String path) {
        return path.equals("/api/v1/products") || path.matches("/api/v1/products/\\d+")
                || path.equals("/api/v1/tables") || path.matches("/api/v1/tables/\\d+")
                || path.equals("/api/v1/orders") || path.matches("/api/v1/orders/\\d+.*")
                || path.equals("/api/v1/reservations") || path.matches("/api/v1/reservations/\\d+.*")
                || path.equals("/api/v1/inventory") || path.matches("/api/v1/inventory/\\d+.*")
                || path.equals("/api/v1/kitchen-tickets") || path.matches("/api/v1/kitchen-tickets/\\d+.*")
                || path.equals("/api/v1/recipes") || path.matches("/api/v1/recipes/\\d+.*");
    }

    private Long readNumber(Object target, String... methodNames) {
        for (String methodName : methodNames) {
            try {
                Method method = target.getClass().getMethod(methodName);
                Object value = method.invoke(target);
                if (value instanceof Number number) return number.longValue();
            } catch (ReflectiveOperationException ignored) { }
        }
        return null;
    }
}
