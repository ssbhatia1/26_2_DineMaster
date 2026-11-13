package com.dinemaster.common.exception;

import com.dinemaster.auth.service.AuthService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.NoHandlerFoundException;
import org.springframework.web.servlet.resource.NoResourceFoundException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;
import java.util.TreeMap;

@RestControllerAdvice
public class ApiExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(AuthService.AuthFailure.class)
    public ResponseEntity<Map<String, Object>> handleAuthFailure(
            AuthService.AuthFailure exception, HttpServletRequest request) {
        HttpStatus status = HttpStatus.valueOf(exception.getStatus());
        String code = switch (exception.getStatus()) {
            case 401 -> "AUTHENTICATION_FAILED";
            case 403 -> "PERMISSION_DENIED";
            case 404 -> "NOT_FOUND";
            case 409 -> "AUTH_CONFLICT";
            case 423 -> "ACCOUNT_LOCKED";
            case 429 -> "RATE_LIMITED";
            case 422 -> "VALIDATION_FAILED";
            default -> "AUTH_REQUEST_FAILED";
        };
        String message = exception.getStatus() == 401
                ? "Authentication failed." : exception.getMessage();
        return ApiErrorResponse.of(status, code, message, null, request);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> handleValidation(
            MethodArgumentNotValidException exception, HttpServletRequest request) {
        Map<String, String> fields = new TreeMap<>();
        exception.getBindingResult().getFieldErrors().forEach(error ->
                fields.putIfAbsent(error.getField(), error.getDefaultMessage()));
        return ApiErrorResponse.of(HttpStatus.UNPROCESSABLE_ENTITY, "VALIDATION_FAILED",
                "Request validation failed.", fields, request);
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<Map<String, Object>> handleConstraint(
            ConstraintViolationException exception, HttpServletRequest request) {
        Map<String, String> fields = new TreeMap<>();
        exception.getConstraintViolations().forEach(violation ->
                fields.putIfAbsent(violation.getPropertyPath().toString(), violation.getMessage()));
        return ApiErrorResponse.of(HttpStatus.UNPROCESSABLE_ENTITY, "VALIDATION_FAILED",
                "Request validation failed.", fields, request);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<Map<String, Object>> handleUnreadable(
            HttpMessageNotReadableException exception, HttpServletRequest request) {
        return ApiErrorResponse.of(HttpStatus.BAD_REQUEST, "BAD_REQUEST",
                "Request body is missing or contains invalid JSON or field values.", null, request);
    }

    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<Map<String, Object>> handleMissingParameter(
            MissingServletRequestParameterException exception, HttpServletRequest request) {
        return ApiErrorResponse.of(HttpStatus.BAD_REQUEST, "BAD_REQUEST",
                "Required query parameter is missing: " + exception.getParameterName(), null, request);
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<Map<String, Object>> handleTypeMismatch(
            MethodArgumentTypeMismatchException exception, HttpServletRequest request) {
        return ApiErrorResponse.of(HttpStatus.BAD_REQUEST, "BAD_REQUEST",
                "Invalid value for parameter: " + exception.getName(), null, request);
    }

    @ExceptionHandler({NoHandlerFoundException.class, NoResourceFoundException.class})
    public ResponseEntity<Map<String, Object>> handleNotFound(Exception exception, HttpServletRequest request) {
        return ApiErrorResponse.of(HttpStatus.NOT_FOUND, "NOT_FOUND", "API endpoint was not found.", null, request);
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<Map<String, Object>> handleMethodNotAllowed(
            HttpRequestMethodNotSupportedException exception, HttpServletRequest request) {
        return ApiErrorResponse.of(HttpStatus.METHOD_NOT_ALLOWED, "METHOD_NOT_ALLOWED",
                "HTTP method is not supported for this endpoint.", null, request);
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<Map<String, Object>> handleConflict(
            DataIntegrityViolationException exception, HttpServletRequest request) {
        return ApiErrorResponse.of(HttpStatus.CONFLICT, "CONFLICT",
                "Request conflicts with existing data or a database constraint.", null, request);
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<Map<String, Object>> handleAccessDenied(
            AccessDeniedException exception, HttpServletRequest request) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        boolean authenticated = authentication != null && authentication.isAuthenticated()
                && !(authentication instanceof AnonymousAuthenticationToken);
        HttpStatus status = authenticated ? HttpStatus.FORBIDDEN : HttpStatus.UNAUTHORIZED;
        return ApiErrorResponse.of(status, authenticated ? "PERMISSION_DENIED" : "AUTH_TOKEN_INVALID",
                authenticated ? "You do not have permission to access this resource."
                        : "Authentication is required.", null, request);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, Object>> handleIllegalArgument(
            IllegalArgumentException exception, HttpServletRequest request) {
        return ApiErrorResponse.of(HttpStatus.BAD_REQUEST, "BAD_REQUEST", "Invalid request.", null, request);
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<Map<String, Object>> handleIllegalState(
            IllegalStateException exception, HttpServletRequest request) {
        return ApiErrorResponse.of(HttpStatus.SERVICE_UNAVAILABLE, "SERVICE_UNAVAILABLE",
                "A required service is unavailable or not configured.", null, request);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> handleUnexpected(
            Exception exception, HttpServletRequest request) {
        log.error("Unhandled API error requestId={} method={} uri={}",
                ApiErrorResponse.requestId(request), request.getMethod(), request.getRequestURI(), exception);
        return ApiErrorResponse.of(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR",
                "An unexpected server error occurred.", null, request);
    }
}
