package com.dinemaster.repository;

import com.dinemaster.entity.Recipe;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface RecipeRepository extends JpaRepository<Recipe, Long> {
    List<Recipe> findByProduct_Id(Long productId);
}