package com.dinemaster.kitchen.repository;
import com.dinemaster.kitchen.entity.Kot;


import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface KotRepository extends JpaRepository<Kot, Long> {
    List<Kot> findByOrder_IdOrderByCreatedAtAsc(Long orderId);

    List<Kot> findByOrder_Restaurant_IdOrderByCreatedAtDesc(Long restaurantId);

    java.util.Optional<Kot> findFirstByOrder_IdOrderByCreatedAtDesc(Long orderId);
}