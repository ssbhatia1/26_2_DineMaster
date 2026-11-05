package com.dinemaster.recipe.controller;



import com.dinemaster.catalog.entity.Product;
import com.dinemaster.catalog.repository.ProductRepository;
import com.dinemaster.inventory.entity.InventoryItem;
import com.dinemaster.inventory.repository.InventoryRepository;
import com.dinemaster.recipe.dto.RecipeRequest;
import com.dinemaster.recipe.entity.Recipe;
import com.dinemaster.recipe.repository.RecipeRepository;
import com.dinemaster.restaurant.entity.Restaurant;

import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/recipes")
public class RecipeController {
    private final RecipeRepository recipeRepository;
    private final ProductRepository productRepository;
    private final InventoryRepository inventoryRepository;

    public RecipeController(RecipeRepository recipeRepository, ProductRepository productRepository,
            InventoryRepository inventoryRepository) {
        this.recipeRepository = recipeRepository;
        this.productRepository = productRepository;
        this.inventoryRepository = inventoryRepository;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('recipe:view')")
    public List<Recipe> list(@RequestParam Long productId) {
        return recipeRepository.findByProduct_Id(productId);
    }

    @PostMapping
    @PreAuthorize("hasAuthority('recipe:manage')")
    @Transactional
    public ResponseEntity<?> create(@Valid @RequestBody RecipeRequest request) {
        Product product = productRepository.findById(request.productId()).orElse(null);
        InventoryItem ingredient = inventoryRepository.findById(request.ingredientId()).orElse(null);
        if (product == null || ingredient == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Product or ingredient not found"));
        }
        if (product.getRestaurant() == null || ingredient.getRestaurant() == null
                || !product.getRestaurant().getId().equals(ingredient.getRestaurant().getId())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Product and ingredient must share a restaurant"));
        }
        Recipe recipe = new Recipe();
        recipe.setProduct(product);
        recipe.setIngredient(ingredient);
        recipe.setQuantityUsed(request.quantityUsed());
        return ResponseEntity.ok(recipeRepository.save(recipe));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('recipe:manage')")
    @Transactional
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody RecipeRequest request) {
        Recipe recipe = recipeRepository.findById(id).orElse(null);
        Product product = productRepository.findById(request.productId()).orElse(null);
        InventoryItem ingredient = inventoryRepository.findById(request.ingredientId()).orElse(null);
        if (recipe == null)
            return ResponseEntity.notFound().build();
        if (product == null || ingredient == null)
            return ResponseEntity.badRequest().body(Map.of("error", "Product or ingredient not found"));
        if (product.getRestaurant() == null || ingredient.getRestaurant() == null
                || !product.getRestaurantId().equals(ingredient.getRestaurant().getId())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Product and ingredient must share a restaurant"));
        }
        recipe.setProduct(product);
        recipe.setIngredient(ingredient);
        recipe.setQuantityUsed(request.quantityUsed());
        return ResponseEntity.ok(recipeRepository.save(recipe));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasAuthority('recipe:manage')")
    public ResponseEntity<?> delete(@PathVariable Long id) {
        if (!recipeRepository.existsById(id))
            return ResponseEntity.notFound().build();
        recipeRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
