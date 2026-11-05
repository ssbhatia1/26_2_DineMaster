package com.dinemaster.restaurant.repository;
import com.dinemaster.restaurant.entity.Restaurant;


import org.springframework.data.jpa.repository.JpaRepository;

public interface RestaurantRepository
        extends JpaRepository<Restaurant, Long> {
}
