package com.dinemaster.restaurant.controller;




import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.restaurant.repository.RestaurantRepository;
import com.dinemaster.security.BranchScopeService;
import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserBranchRepository;
import jakarta.validation.Valid;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/branches")
public class RestaurantController {

    private final RestaurantRepository restaurantRepository;
    private final BranchScopeService branchScope;
    private final UserBranchRepository userBranches;

    public RestaurantController(RestaurantRepository restaurantRepository, BranchScopeService branchScope,
            UserBranchRepository userBranches) {
        this.restaurantRepository = restaurantRepository;
        this.branchScope = branchScope;
        this.userBranches = userBranches;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('branch:view')")
    public ResponseEntity<?> getAllRestaurants(Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        return ResponseEntity.ok(restaurantRepository.findAllById(userBranches.findBranchIds(user.getId())).stream()
                .filter(branch -> java.util.Objects.equals(branch.getTenantId(), user.getTenantId())).toList());
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('branch:view')")
    public ResponseEntity<?> getRestaurantById(@PathVariable Long id) {
        return restaurantRepository.findById(id)
                .<ResponseEntity<?>>map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Restaurant not found")));
    }

    @PostMapping
    @PreAuthorize("hasAuthority('branch:create')")
    public ResponseEntity<?> createRestaurant(
            @Valid @RequestBody Restaurant restaurant, Authentication authentication) {

        if (restaurant == null || restaurant.getName() == null
                || restaurant.getName().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Restaurant name is required"));
        }

        User user = branchScope.requireUser(authentication);
        if (user.getTenantId() == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Assign a tenant before creating a branch"));
        }
        restaurant.setId(null);
        restaurant.setName(restaurant.getName().trim());
        restaurant.setCreatedAt(null);
        restaurant.setTenantId(user.getTenantId());

        Restaurant saved = restaurantRepository.save(restaurant);
        java.util.List<Long> assigned = new java.util.ArrayList<>(userBranches.findBranchIds(user.getId()));
        assigned.add(saved.getId());
        userBranches.replaceBranches(user.getId(), assigned);

        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('branch:update')")
    public ResponseEntity<?> updateRestaurant(
            @PathVariable Long id,
            @Valid @RequestBody Restaurant request) {

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
    @PreAuthorize("hasAuthority('branch:update')")
    public ResponseEntity<?> deleteRestaurant(@PathVariable Long id) {
        if (!restaurantRepository.existsById(id)) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", "Restaurant not found"));
        }

        restaurantRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
