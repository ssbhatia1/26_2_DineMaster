package com.dinemaster.dto;

public record AuthResponse(String token, UserResponse user) {
}