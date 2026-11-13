package com.dinemaster.auth.repository;

import com.dinemaster.auth.entity.RefreshToken;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface RefreshTokenRepository extends JpaRepository<RefreshToken, UUID> {
    Optional<RefreshToken> findByTokenHash(String tokenHash);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select token from RefreshToken token where token.tokenHash = :tokenHash")
    Optional<RefreshToken> findByTokenHashForUpdate(@Param("tokenHash") String tokenHash);
    List<RefreshToken> findAllByFamilyIdAndRevokedAtIsNull(UUID familyId);
    List<RefreshToken> findAllByUserIdAndRevokedAtIsNull(Long userId);
    List<RefreshToken> findAllByDeviceIdAndRevokedAtIsNull(UUID deviceId);
}
