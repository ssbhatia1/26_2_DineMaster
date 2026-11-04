package com.dinemaster.diningtable.repository;





import com.dinemaster.diningtable.entity.DiningTable;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.restaurant.entity.Restaurant;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface DiningTableRepository
        extends JpaRepository<DiningTable, Long> {

    List<DiningTable> findByStatus(String status);

    boolean existsByTableNumber(String tableNumber);

    List<DiningTable> findByRestaurant_IdOrderByTableNumberAsc(Long restaurantId);
}
