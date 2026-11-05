package com.dinemaster.inventory.repository;
import com.dinemaster.inventory.entity.InventoryItem;


import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface InventoryRepository extends JpaRepository<InventoryItem, Long> {
    List<InventoryItem> findByRestaurant_IdOrderByItemNameAsc(Long restaurantId);
}