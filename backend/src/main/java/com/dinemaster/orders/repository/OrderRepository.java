package com.dinemaster.orders.repository;





import com.dinemaster.orders.entity.Order;
import com.dinemaster.restaurant.entity.Restaurant;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface OrderRepository extends JpaRepository<Order, Long> {

    List<Order> findByRestaurant_IdOrderByOrderTimeDesc(Long restaurantId);

    List<Order> findByStatusIgnoreCaseOrderByOrderTimeDesc(String status);

    Optional<Order> findByIdAndTableSession_Id(Long orderId, Long sessionId);

    @Query("select count(o) from Order o where o.diningTable.id = :tableId "
            + "and upper(o.status) not in ('COMPLETED', 'CANCELLED')")
    long countOpenOrdersForTable(@Param("tableId") Long tableId);
}
