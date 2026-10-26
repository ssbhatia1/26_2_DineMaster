
package com.dinemaster.controller;

import com.dinemaster.entity.Restaurant;
import com.dinemaster.repository.RestaurantRepository;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/restaurants")
public class RestaurantController {

    private final RestaurantRepository restaurantRepository;

    public RestaurantController(RestaurantRepository restaurantRepository) {
        this.restaurantRepository = restaurantRepository;
    }

    @GetMapping
    public ResponseEntity<?> getAllRestaurants() {
        return ResponseEntity.ok(restaurantRepository.findAll());
    }

    @GetMapping("/{id}")
    public ResponseEntity<?> getRestaurantById(@PathVariable Long id) {
        return restaurantRepository.findById(id)
                .<ResponseEntity<?>>map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Restaurant not found")));
    }

    @PostMapping
    public ResponseEntity<?> createRestaurant(
            @RequestBody Restaurant restaurant) {

        if (restaurant == null || restaurant.getName() == null
                || restaurant.getName().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Restaurant name is required"));
        }

        restaurant.setId(null);
        restaurant.setName(restaurant.getName().trim());
        restaurant.setCreatedAt(null);

        Restaurant saved = restaurantRepository.save(restaurant);

        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }

    @PutMapping("/{id}")
    public ResponseEntity<?> updateRestaurant(
            @PathVariable Long id,
            @RequestBody Restaurant request) {

        if (request.getName() == null || request.getName().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Restaurant name is required"));
        }

        return restaurantRepository.findById(id)
                .<ResponseEntity<?>>map(existing -> {
                    existing.setName(request.getName().trim());
                    existing.setAddress(request.getAddress());
                    existing.setPhone(request.getPhone());

                    return ResponseEntity.ok(
                            restaurantRepository.save(existing));
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Restaurant not found")));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteRestaurant(@PathVariable Long id) {
        if (!restaurantRepository.existsById(id)) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", "Restaurant not found"));
        }

        restaurantRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
