package com.dinemaster.auth.repository;

import com.dinemaster.auth.entity.AuthAuditLog;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.UUID;
import java.util.List;

public interface AuthAuditLogRepository extends JpaRepository<AuthAuditLog, UUID> {
    List<AuthAuditLog> findTop100ByUserIdAndTenantIdOrderByCreatedAtDesc(Long userId, Long tenantId);
}
