package com.dinemaster.auth.dto;

import com.dinemaster.auth.entity.AuthAuditLog;
import java.time.OffsetDateTime;
import java.util.UUID;

public record AuditLogResponse(
        UUID id,
        Long userId,
        String username,
        String action,
        boolean success,
        OffsetDateTime createdAt,
        Long actorUserId,
        Long tenantId,
        Long branchId,
        String reason) {
    public static AuditLogResponse from(AuthAuditLog log) {
        return new AuditLogResponse(log.getId(), log.getUserId(), log.getUsername(), log.getAction(),
                log.isSuccess(), log.getCreatedAt(), log.getActorUserId(), log.getTenantId(),
                log.getBranchId(), log.getReason());
    }
}
