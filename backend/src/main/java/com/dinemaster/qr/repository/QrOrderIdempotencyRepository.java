package com.dinemaster.qr.repository;

import com.dinemaster.qr.entity.QrOrderIdempotency;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface QrOrderIdempotencyRepository extends JpaRepository<QrOrderIdempotency, Long> {
    Optional<QrOrderIdempotency> findBySession_IdAndIdempotencyKey(Long sessionId, String idempotencyKey);
}
