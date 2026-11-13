package com.dinemaster.restaurant.repository;

import com.dinemaster.restaurant.entity.BranchHours;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface BranchHoursRepository extends JpaRepository<BranchHours, Long> {
    List<BranchHours> findAllByBranchIdOrderByWeekday(Long branchId);
    void deleteAllByBranchId(Long branchId);
}
