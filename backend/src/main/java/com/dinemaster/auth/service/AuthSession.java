package com.dinemaster.auth.service;

import com.dinemaster.user.dto.UserResponse;
import java.util.List;
import java.util.UUID;

public record AuthSession(String accessToken, String refreshToken, long expiresIn, UserResponse user,
        Long tenantId, List<Long> branchIds, UUID deviceId, int permVersion) { }
