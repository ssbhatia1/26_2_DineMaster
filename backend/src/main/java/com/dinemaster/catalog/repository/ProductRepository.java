package com.dinemaster.catalog.repository;





import com.dinemaster.catalog.entity.Category;
import com.dinemaster.catalog.entity.Product;
import com.dinemaster.restaurant.entity.Restaurant;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface ProductRepository extends JpaRepository<Product, Long> {

    List<Product> findByAvailableTrue();

    List<Product> findByRestaurant_IdAndAvailableTrue(Long restaurantId);

    List<Product> findByRestaurant_Id(Long restaurantId);

    Optional<Product> findByIdAndRestaurant_Id(Long id, Long restaurantId);

    List<Product> findByCategoryIgnoreCase(String category);

    List<Product> findByRestaurant_IdAndCategoryIgnoreCase(Long restaurantId, String category);
}
