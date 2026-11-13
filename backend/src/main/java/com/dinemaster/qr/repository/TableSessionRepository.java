package com.dinemaster.qr.repository;

import com.dinemaster.qr.entity.TableSession;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TableSessionRepository extends JpaRepository<TableSession, Long> {
    @Query("select s from TableSession s where s.tokenHash = :hash")
    Optional<TableSession> findByTokenHash(@Param("hash") String hash);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select s from TableSession s where s.id = :id")
    Optional<TableSession> lockById(@Param("id") Long id);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select s from TableSession s where s.table.id = :tableId and s.closedAt is null order by s.openedAt desc")
    java.util.List<TableSession> lockOpenForTable(@Param("tableId") Long tableId);
}
