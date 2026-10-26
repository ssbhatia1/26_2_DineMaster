package com.dinemaster.controller;

import com.dinemaster.dto.UserRequest;
import com.dinemaster.dto.UserResponse;
import com.dinemaster.entity.User;
import com.dinemaster.repository.UserRepository;
import com.dinemaster.security.Roles;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@RequestMapping("/api/users")
@PreAuthorize("hasAnyRole('OWNER','MANAGER')")
public class UserController {
    private final UserRepository repository;
    private final PasswordEncoder encoder;

    public UserController(UserRepository repository, PasswordEncoder encoder) {
        this.repository = repository;
        this.encoder = encoder;
    }

    @GetMapping
    @PreAuthorize("hasAnyRole('OWNER','MANAGER')")
    public java.util.List<UserResponse> list() {
        return repository.findAll().stream().map(UserResponse::from).toList();
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('OWNER','MANAGER')")
    public ResponseEntity<?> get(@PathVariable Long id) {
        return repository.findById(id).<ResponseEntity<?>>map(user -> ResponseEntity.ok(UserResponse.from(user)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('OWNER','MANAGER')")
    public ResponseEntity<?> create(@Valid @RequestBody UserRequest request) {
        if (request.password() == null || request.password().isBlank())
            return ResponseEntity.badRequest().body(Map.of("error", "Password is required"));
        if (repository.existsByUsername(request.username().trim()))
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Username already exists"));
        User user = new User();
        copy(request, user, true);
        return ResponseEntity.status(HttpStatus.CREATED).body(UserResponse.from(repository.save(user)));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAnyRole('OWNER','MANAGER')")
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody UserRequest request) {
        User user = repository.findById(id).orElse(null);
        if (user == null)
            return ResponseEntity.notFound().build();
        if (!user.getUsername().equals(request.username()) && repository.existsByUsername(request.username().trim()))
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Username already exists"));
        copy(request, user, false);
        return ResponseEntity.ok(UserResponse.from(repository.save(user)));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasAnyRole('OWNER','MANAGER')")
    public ResponseEntity<?> delete(@PathVariable Long id) {
        if (!repository.existsById(id))
            return ResponseEntity.notFound().build();
        repository.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    private void copy(UserRequest request, User user, boolean requirePassword) {
        user.setName(request.name().trim());
        user.setUsername(request.username().trim());
        user.setRole(Roles.canonical(request.role()));
        if (requirePassword || (request.password() != null && !request.password().isBlank()))
            user.setPassword(encoder.encode(request.password()));
        if (request.active() != null)
            user.setActive(request.active());
        user.setContactDetails(request.contactDetails());
        user.setShiftTiming(request.shiftTiming());
    }
}