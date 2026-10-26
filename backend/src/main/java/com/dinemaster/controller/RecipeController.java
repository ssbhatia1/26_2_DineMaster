package com.dinemaster.controller;

import com.dinemaster.dto.RecipeRequest;
import com.dinemaster.entity.InventoryItem;
import com.dinemaster.entity.Product;
import com.dinemaster.entity.Recipe;
import com.dinemaster.repository.InventoryRepository;
import com.dinemaster.repository.ProductRepository;
import com.dinemaster.repository.RecipeRepository;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/recipes")
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
    public List<Recipe> list(@RequestParam Long productId) {
        return recipeRepository.findByProduct_Id(productId);
    }

    @PostMapping
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
    @Transactional
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody RecipeRequest request) {
        Recipe recipe = recipeRepository.findById(id).orElse(null);
        Product product = productRepository.findById(request.productId()).orElse(null);
        InventoryItem ingredient = inventoryRepository.findById(request.ingredientId()).orElse(null);
        if (recipe == null)
            return ResponseEntity.notFound().build();
        if (product == null || ingredient == null)
            return ResponseEntity.badRequest().body(Map.of("error", "Product or ingredient not found"));
        recipe.setProduct(product);
        recipe.setIngredient(ingredient);
        recipe.setQuantityUsed(request.quantityUsed());
        return ResponseEntity.ok(recipeRepository.save(recipe));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> delete(@PathVariable Long id) {
        if (!recipeRepository.existsById(id))
            return ResponseEntity.notFound().build();
        recipeRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}