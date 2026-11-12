package com.dinemaster.restaurant.repository;




import com.dinemaster.restaurant.entity.Restaurant;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface RestaurantRepository
        extends JpaRepository<Restaurant, Long> {

    List<Restaurant> findAllByTenantId(Long tenantId);
}
