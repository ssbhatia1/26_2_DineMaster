package com.dinemaster.diningtable.controller;

import com.dinemaster.diningtable.dto.FloorRequest;
import com.dinemaster.diningtable.entity.Floor;
import com.dinemaster.diningtable.repository.FloorRepository;
import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.restaurant.repository.RestaurantRepository;
import com.dinemaster.security.BranchScopeService;
import com.dinemaster.user.entity.User;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/floors")
public class FloorController {
    private final FloorRepository floors;
    private final RestaurantRepository branches;
    private final BranchScopeService branchScope;

    public FloorController(FloorRepository floors, RestaurantRepository branches, BranchScopeService branchScope) {
        this.floors = floors;
        this.branches = branches;
        this.branchScope = branchScope;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('table:view')")
    public ResponseEntity<?> list(@RequestParam Long branchId,
            @RequestParam(defaultValue = "false") boolean includeInactive, Authentication authentication) {
        branchScope.requireBranch(authentication, branchId);
        if (includeInactive && !authentication.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("table:manage_layout"))) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("error", "Layout permission required"));
        }
        List<Floor> result = includeInactive
                ? floors.findAllByBranchIdOrderByDisplayOrderAscNameAsc(branchId)
                : floors.findAllByBranchIdAndActiveTrueOrderByDisplayOrderAscNameAsc(branchId);
        return ResponseEntity.ok(Map.of("items", result));
    }

    @PostMapping
    @PreAuthorize("hasAuthority('table:manage_layout')")
    public ResponseEntity<?> create(@RequestParam Long branchId, @Valid @RequestBody FloorRequest request,
            Authentication authentication) {
        branchScope.requireBranch(authentication, branchId);
        User user = branchScope.requireUser(authentication);
        Restaurant branch = branches.findById(branchId).orElse(null);
        if (branch == null || !java.util.Objects.equals(user.getTenantId(), branch.getTenantId())) return ResponseEntity.notFound().build();
        if (floors.existsByBranchIdAndNameIgnoreCase(branchId, request.name().trim())) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Floor name already exists"));
        }
        Floor saved = floors.save(new Floor(user.getTenantId(), branchId, request.name().trim(),
                request.description(), request.displayOrder()));
        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('table:manage_layout')")
    public ResponseEntity<?> update(@PathVariable Long id, @RequestParam Long branchId,
            @Valid @RequestBody FloorRequest request, Authentication authentication) {
        branchScope.requireBranch(authentication, branchId);
        User user = branchScope.requireUser(authentication);
        Floor floor = user.getTenantId() == null ? null
                : floors.findByIdAndBranchIdAndTenantId(id, branchId, user.getTenantId()).orElse(null);
        if (floor == null) return ResponseEntity.notFound().build();
        if (!floor.getName().equalsIgnoreCase(request.name().trim())
                && floors.existsByBranchIdAndNameIgnoreCase(branchId, request.name().trim())) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", "Floor name already exists"));
        }
        floor.setName(request.name().trim());
        floor.setDescription(request.description());
        floor.setDisplayOrder(request.displayOrder());
        floor.setActive(request.active());
        return ResponseEntity.ok(floors.save(floor));
    }
}
