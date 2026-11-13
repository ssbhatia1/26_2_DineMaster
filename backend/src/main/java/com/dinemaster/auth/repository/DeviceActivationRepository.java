package com.dinemaster.auth.repository;

import com.dinemaster.auth.entity.DeviceActivation;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

public interface DeviceActivationRepository extends JpaRepository<DeviceActivation, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from DeviceActivation a where a.codeHash = :hash")
    Optional<DeviceActivation> findByCodeHashForUpdate(@Param("hash") String hash);
}
