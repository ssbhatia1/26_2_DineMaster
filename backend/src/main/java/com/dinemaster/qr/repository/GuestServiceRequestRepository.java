package com.dinemaster.qr.repository;

import com.dinemaster.qr.entity.GuestServiceRequest;
import java.time.OffsetDateTime;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface GuestServiceRequestRepository extends JpaRepository<GuestServiceRequest, Long> {
    List<GuestServiceRequest> findBySession_Branch_IdAndStatusOrderByCreatedAtAsc(Long branchId, String status);
    Optional<GuestServiceRequest> findFirstBySession_IdAndStatusAndCreatedAtAfterOrderByCreatedAtDesc(
            Long sessionId, String status, OffsetDateTime after);
}
