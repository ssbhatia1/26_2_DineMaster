package com.dinemaster.auth.dto;



import com.dinemaster.user.dto.UserResponse;
import java.util.List;
import java.util.UUID;

public record AuthResponse(String token, String accessToken, String refreshToken, String tokenType,
        long expiresIn, UserResponse user, Long tenantId, List<Long> branchIds,
        UUID deviceId, int permVersion) {
}
