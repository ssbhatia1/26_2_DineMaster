
package com.dinemaster.controller;

import com.dinemaster.entity.Category;
import com.dinemaster.entity.Product;
import com.dinemaster.entity.Restaurant;
import com.dinemaster.repository.CategoryRepository;
import com.dinemaster.repository.ProductRepository;
import com.dinemaster.repository.RestaurantRepository;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/products")
public class ProductController {

    private final ProductRepository productRepository;
    private final CategoryRepository categoryRepository;
    private final RestaurantRepository restaurantRepository;

    public ProductController(
            ProductRepository productRepository,
            CategoryRepository categoryRepository,
            RestaurantRepository restaurantRepository) {
        this.productRepository = productRepository;
        this.categoryRepository = categoryRepository;
        this.restaurantRepository = restaurantRepository;
    }

    // GET: Fetch available products
    @GetMapping
    public ResponseEntity<List<Product>> getAllProducts(
            @RequestParam(required = false) Long restaurantId) {
        return ResponseEntity.ok(restaurantId == null
                ? productRepository.findByAvailableTrue()
                : productRepository.findByRestaurant_IdAndAvailableTrue(restaurantId));
    }

    // GET: Fetch all products, including unavailable products
    @GetMapping("/all")
    public ResponseEntity<List<Product>> getAllProductsForManagement() {
        return ResponseEntity.ok(productRepository.findAll());
    }

    // GET: Fetch a product by ID
    @GetMapping("/{id}")
    public ResponseEntity<?> getProductById(@PathVariable Long id) {
        return productRepository.findById(id)
                .<ResponseEntity<?>>map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Product not found")));
    }

    // GET: Fetch products by category name
    @GetMapping("/category/{category}")
    public ResponseEntity<List<Product>> getProductsByCategory(
            @PathVariable String category,
            @RequestParam(required = false) Long restaurantId) {
        return ResponseEntity.ok(restaurantId == null
                ? productRepository.findByCategoryIgnoreCase(category)
                : productRepository.findByRestaurant_IdAndCategoryIgnoreCase(
                        restaurantId, category));
    }

    // POST: Create a product
    @PostMapping
    public ResponseEntity<?> createProduct(@RequestBody Product product) {
        ResponseEntity<Map<String, String>> validation = validateProduct(product);

        if (validation != null) {
            return ResponseEntity.badRequest().body(validation.getBody());
        }

        String categoryName = findCategoryName(product.getCategory());

        if (categoryName == null) {
            return ResponseEntity.badRequest().body(
                    Map.of("error", "Category does not exist. Create the category first."));
        }

        product.setId(null);
        product.setName(product.getName().trim());
        product.setCategory(categoryName);
        ResponseEntity<?> restaurantError = attachRestaurant(product);
        if (restaurantError != null) {
            return restaurantError;
        }

        if (product.getGstPercentage() == null) {
            product.setGstPercentage(new BigDecimal("5.00"));
        }

        Product savedProduct = productRepository.save(product);

        return ResponseEntity.status(HttpStatus.CREATED).body(savedProduct);
    }

    // PUT: Update a product
    @PutMapping("/{id}")
    public ResponseEntity<?> updateProduct(
            @PathVariable Long id,
            @RequestBody Product request) {

        ResponseEntity<Map<String, String>> validation = validateProduct(request);

        if (validation != null) {
            return ResponseEntity.badRequest().body(validation.getBody());
        }

        return productRepository.findById(id)
                .<ResponseEntity<?>>map(existingProduct -> {
                    String categoryName = findCategoryName(request.getCategory());

                    if (categoryName == null) {
                        return ResponseEntity.badRequest().body(
                                Map.of("error", "Category does not exist."));
                    }

                    copyProductFields(request, existingProduct);
                    existingProduct.setCategory(categoryName);
                    if (request.getRestaurantId() != null) {
                        ResponseEntity<?> restaurantError = attachRestaurant(request);
                        if (restaurantError != null) {
                            return restaurantError;
                        }
                        existingProduct.setRestaurant(request.getRestaurant());
                    }

                    return ResponseEntity.ok(
                            productRepository.save(existingProduct));
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Product not found")));
    }

    // PATCH: Update only product availability
    @PatchMapping("/{id}/availability")
    public ResponseEntity<?> updateAvailability(
            @PathVariable Long id,
            @RequestBody Map<String, Boolean> request) {

        Boolean available = request.get("is_available");
        if (available == null) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "is_available is required"));
        }

        return productRepository.findById(id)
                .<ResponseEntity<?>>map(product -> {
                    product.setAvailable(available);
                    return ResponseEntity.ok(productRepository.save(product));
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Product not found")));
    }
    // DELETE: Delete a product
    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteProduct(@PathVariable Long id) {
        if (!productRepository.existsById(id)) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", "Product not found"));
        }

        productRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    private ResponseEntity<Map<String, String>> validateProduct(
            Product product) {

        if (product == null) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Product data is required"));
        }

        if (product.getName() == null || product.getName().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Product name is required"));
        }

        if (product.getName().trim().length() > 150) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Product name cannot exceed 150 characters"));
        }

        if (product.getPrice() == null
                || product.getPrice().compareTo(BigDecimal.ZERO) < 0) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "A non-negative product price is required"));
        }

        if (product.getCategory() == null
                || product.getCategory().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Product category is required"));
        }

        if (product.getVeg() == null || product.getVeg() < 0 || product.getVeg() > 3) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "is_veg must be one of 0, 1, 2, or 3"));
        }

        if (product.getGstPercentage() != null
                && (product.getGstPercentage().compareTo(BigDecimal.ZERO) < 0
                        || product.getGstPercentage()
                                .compareTo(new BigDecimal("100")) > 0)) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "GST percentage must be between 0 and 100"));
        }

        return null;
    }

    private ResponseEntity<?> attachRestaurant(Product product) {
        Long restaurantId = product.getRestaurantId();
        if (restaurantId == null) {
            return null;
        }
        Restaurant restaurant = restaurantRepository.findById(restaurantId).orElse(null);
        if (restaurant == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Restaurant not found"));
        }
        product.setRestaurant(restaurant);
        return null;
    }

    private String findCategoryName(String requestedName) {
        if (requestedName == null || requestedName.isBlank()) {
            return null;
        }

        return categoryRepository.findAll().stream()
                .map(Category::getName)
                .filter(name -> name.equalsIgnoreCase(requestedName.trim()))
                .findFirst()
                .orElse(null);
    }

    private void copyProductFields(Product source, Product target) {
        target.setName(source.getName().trim());
        target.setDescription(source.getDescription());
        target.setIngredients(source.getIngredients());
        target.setPrice(source.getPrice());
        target.setVeg(source.getVeg());
        target.setImagePath(source.getImagePath());
        target.setAvailable(source.isAvailable());
        target.setGstPercentage(
                source.getGstPercentage() == null
                        ? new BigDecimal("5.00")
                        : source.getGstPercentage());
        target.setDietaryPreferences(source.getDietaryPreferences());
        target.setTastePreferences(source.getTastePreferences());
        target.setAttributes(source.getAttributes());
        target.setCustomDietaryNotes(source.getCustomDietaryNotes());
        target.setRecipeSteps(source.getRecipeSteps());
        target.setPrepTime(source.getPrepTime());
        target.setCookTime(source.getCookTime());
        target.setServings(source.getServings());
        target.setDifficulty(source.getDifficulty());
        target.setVideoPath(source.getVideoPath());
    }
}

