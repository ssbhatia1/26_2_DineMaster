package com.dinemaster.orders.repository;





import com.dinemaster.kitchen.entity.Kot;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.orders.entity.OrderItem;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface OrderItemRepository extends JpaRepository<OrderItem, Long> {

    List<OrderItem> findByOrder_Id(Long orderId);

    List<OrderItem> findByKot_Id(Long kotId);
}
