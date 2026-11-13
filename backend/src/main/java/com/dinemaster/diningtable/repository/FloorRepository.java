package com.dinemaster.diningtable.repository;

import com.dinemaster.diningtable.entity.Floor;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface FloorRepository extends JpaRepository<Floor, Long> {
    List<Floor> findAllByBranchIdAndActiveTrueOrderByDisplayOrderAscNameAsc(Long branchId);
    List<Floor> findAllByBranchIdOrderByDisplayOrderAscNameAsc(Long branchId);
    Optional<Floor> findByIdAndBranchIdAndTenantId(Long id, Long branchId, Long tenantId);
    Optional<Floor> findByIdAndBranchId(Long id, Long branchId);
    boolean existsByBranchIdAndNameIgnoreCase(Long branchId, String name);
}
