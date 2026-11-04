package com.dinemaster.auth.dto;



import com.dinemaster.user.dto.UserResponse;
import com.dinemaster.user.entity.User;

public record AuthResponse(String token, UserResponse user) {
}
