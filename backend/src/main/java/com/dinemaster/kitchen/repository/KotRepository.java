package com.dinemaster.kitchen.repository;




import com.dinemaster.kitchen.entity.Kot;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.restaurant.entity.Restaurant;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface KotRepository extends JpaRepository<Kot, Long> {
    List<Kot> findByOrder_IdOrderByCreatedAtAsc(Long orderId);

    List<Kot> findByOrder_Restaurant_IdOrderByCreatedAtDesc(Long restaurantId);
}
