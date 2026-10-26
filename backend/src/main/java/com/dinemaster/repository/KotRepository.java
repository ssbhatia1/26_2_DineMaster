package com.dinemaster.repository;

import com.dinemaster.entity.Kot;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface KotRepository extends JpaRepository<Kot, Long> {
    List<Kot> findByOrder_IdOrderByCreatedAtAsc(Long orderId);

    List<Kot> findByOrder_Restaurant_IdOrderByCreatedAtDesc(Long restaurantId);
}