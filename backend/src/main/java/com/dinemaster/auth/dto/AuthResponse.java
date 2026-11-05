package com.dinemaster.auth.dto;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.dto.UserResponse;


public record AuthResponse(String token, UserResponse user) {
}