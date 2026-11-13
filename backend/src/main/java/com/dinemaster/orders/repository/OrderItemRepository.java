package com.dinemaster.orders.repository;





import com.dinemaster.kitchen.entity.Kot;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.orders.entity.OrderItem;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface OrderItemRepository extends JpaRepository<OrderItem, Long> {

    List<OrderItem> findByOrder_Id(Long orderId);

    List<OrderItem> findByKot_Id(Long kotId);

    @Modifying
    @Query(value = "UPDATE order_items SET kot_id = :kotId WHERE id = :itemId AND order_id = :orderId",
            nativeQuery = true)
    int assignToKot(@Param("itemId") Long itemId, @Param("orderId") Long orderId,
            @Param("kotId") Long kotId);
}
