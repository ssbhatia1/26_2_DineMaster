package com.dinemaster.recipe.repository;
import com.dinemaster.recipe.entity.Recipe;


import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface RecipeRepository extends JpaRepository<Recipe, Long> {
    List<Recipe> findByProduct_Id(Long productId);
}