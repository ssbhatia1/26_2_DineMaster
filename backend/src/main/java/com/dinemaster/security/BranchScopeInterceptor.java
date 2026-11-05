package com.dinemaster.security;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

@Component
public class BranchScopeInterceptor implements HandlerInterceptor {
    private final BranchScopeService scope;
    public BranchScopeInterceptor(BranchScopeService scope) { this.scope = scope; }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()
                || request.getRequestURI().startsWith("/api/v1/auth/")) return true;

        String uri = request.getRequestURI();
        String branchParameter = request.getParameter("branchId");
        if (branchParameter == null) branchParameter = request.getParameter("restaurantId");
        if (branchParameter != null) {
            scope.requireBranch(authentication, parseId(branchParameter, "restaurantId"));
        }

        String[] path = uri.split("/");
        if (path.length >= 4 && path[1].equals("api") && path[2].equals("v1")) {
            if (path[3].equals("kitchen-tickets") && path.length >= 6 && path[4].equals("order")) {
                Long branch = scope.branchForResource("/api/v1/orders/" + path[5], parseId(path[5], "orderId"));
                if (branch == null) throw new org.springframework.security.access.AccessDeniedException(
                        "Order is outside the user's assigned scope");
                scope.requireBranch(authentication, branch);
            } else if (path.length >= 5 && isBranchResource(path[3]) && path[4].matches("\\d+")) {
                Long branch = scope.branchForResource(uri, parseId(path[4], "id"));
                if (branch == null) throw new org.springframework.security.access.AccessDeniedException(
                        "Resource is outside the user's assigned scope");
                scope.requireBranch(authentication, branch);
            }
        }

        if ("GET".equalsIgnoreCase(request.getMethod()) && isBranchCollectionOrNested(path)
                && branchParameter == null) {
            if (path[3].equals("recipes")) {
                String productId = request.getParameter("productId");
                if (productId == null) {
                    throw new IllegalArgumentException("productId is required for this branch-scoped endpoint");
                }
                Long branch = scope.branchForProduct(parseId(productId, "productId"));
                if (branch == null) throw new org.springframework.security.access.AccessDeniedException(
                        "Product is outside the user's assigned scope");
                scope.requireBranch(authentication, branch);
            } else {
                throw new IllegalArgumentException("restaurantId is required for this branch-scoped endpoint");
            }
        }
        return true;
    }

    private boolean isBranchResource(String segment) {
        return java.util.Set.of("branches", "products", "tables", "orders", "reservations",
                "inventory", "kitchen-tickets", "recipes").contains(segment);
    }

    private boolean isBranchCollectionOrNested(String[] path) {
        if (path.length < 4 || !isBranchResource(path[3]) || path[3].equals("branches")) return false;
        if (path[3].equals("kitchen-tickets") && path.length >= 6 && path[4].equals("order")) return false;
        if (path.length == 4) return true;
        // A numeric segment identifies an individual branch-owned resource, checked above.
        return !path[4].matches("\\d+");
    }

    private Long parseId(String value, String name) {
        try {
            long id = Long.parseLong(value);
            if (id <= 0) throw new NumberFormatException();
            return id;
        }
        catch (NumberFormatException exception) { throw new IllegalArgumentException(name + " must be a positive integer"); }
    }
}
