package com.dinemaster.orders.repository;





import com.dinemaster.orders.entity.Order;
import com.dinemaster.restaurant.entity.Restaurant;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface OrderRepository extends JpaRepository<Order, Long> {

    List<Order> findByRestaurant_IdOrderByOrderTimeDesc(Long restaurantId);

    List<Order> findByStatusIgnoreCaseOrderByOrderTimeDesc(String status);
}
