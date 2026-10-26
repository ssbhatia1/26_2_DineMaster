
package com.dinemaster.repository;

import com.dinemaster.entity.DiningTable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface DiningTableRepository
        extends JpaRepository<DiningTable, Long> {

    List<DiningTable> findByStatus(String status);

    boolean existsByTableNumber(String tableNumber);

    List<DiningTable> findByRestaurant_IdOrderByTableNumberAsc(Long restaurantId);
}
