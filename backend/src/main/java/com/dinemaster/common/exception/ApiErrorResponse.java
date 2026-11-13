package com.dinemaster.common.exception;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;

public final class ApiErrorResponse {
    private static final Pattern SAFE_REQUEST_ID = Pattern.compile("[A-Za-z0-9._:-]{1,100}");

    private ApiErrorResponse() { }

    public static ResponseEntity<Map<String, Object>> of(
            HttpStatus status, String code, String message, Object details, HttpServletRequest request) {
        String requestId = requestId(request);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("timestamp", java.time.Instant.now().toString());
        body.put("status", status.value());
        body.put("code", code);
        body.put("message", message);
        body.put("details", details == null ? java.util.List.of() : details);
        body.put("requestId", requestId);
        return ResponseEntity.status(status).header("X-Request-Id", requestId).body(body);
    }

    public static String requestId(HttpServletRequest request) {
        String supplied = request == null ? null : request.getHeader("X-Request-Id");
        if (supplied != null && SAFE_REQUEST_ID.matcher(supplied).matches()) return supplied;
        if (request == null) return UUID.randomUUID().toString();
        Object existing = request.getAttribute("api.requestId");
        if (existing instanceof String value && SAFE_REQUEST_ID.matcher(value).matches()) return value;
        String generated = UUID.randomUUID().toString();
        request.setAttribute("api.requestId", generated);
        return generated;
    }
}
