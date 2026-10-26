
package com.dinemaster.repository;

import com.dinemaster.entity.Product;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface ProductRepository extends JpaRepository<Product, Long> {

    List<Product> findByAvailableTrue();

    List<Product> findByRestaurant_IdAndAvailableTrue(Long restaurantId);

    Optional<Product> findByIdAndRestaurant_Id(Long id, Long restaurantId);

    List<Product> findByCategoryIgnoreCase(String category);

    List<Product> findByRestaurant_IdAndCategoryIgnoreCase(Long restaurantId, String category);
}
