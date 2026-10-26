package com.dinemaster.controller;

import com.dinemaster.dto.AuthResponse;
import com.dinemaster.dto.LoginRequest;
import com.dinemaster.dto.UserResponse;
import com.dinemaster.repository.UserRepository;
import com.dinemaster.security.Roles;
import com.dinemaster.service.JwtService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;

    public AuthController(UserRepository userRepository, PasswordEncoder passwordEncoder, JwtService jwtService) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@Valid @RequestBody LoginRequest request) {
        return userRepository.findByUsername(request.username().trim()).filter(user -> user.isActive())
                .filter(user -> passwordEncoder.matches(request.password(), user.getPassword()))
                .<ResponseEntity<?>>map(user -> {
                    user.setRole(Roles.canonical(user.getRole()));
                    return ResponseEntity.ok(new AuthResponse(jwtService.createToken(user), UserResponse.from(user)));
                })
                .orElseGet(() -> ResponseEntity.status(401).body(Map.of("error", "Invalid username or password")));
    }
}