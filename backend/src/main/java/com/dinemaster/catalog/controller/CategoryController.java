package com.dinemaster.catalog.controller;




import com.dinemaster.catalog.dto.CategoryRequest;
import com.dinemaster.catalog.entity.Category;
import com.dinemaster.catalog.repository.CategoryRepository;

import jakarta.validation.Valid;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import com.dinemaster.security.BranchScopeService;
import com.dinemaster.user.entity.User;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/categories")
public class CategoryController {

    private final CategoryRepository categoryRepository;
    private final BranchScopeService branchScope;

    public CategoryController(CategoryRepository categoryRepository, BranchScopeService branchScope) {
        this.categoryRepository = categoryRepository;
        this.branchScope = branchScope;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('menu:view')")
    public ResponseEntity<List<Category>> getAllCategories(Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        return ResponseEntity.ok(categoryRepository.findAllByTenantId(user.getTenantId()));
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('menu:view')")
    public ResponseEntity<?> getCategoryById(@PathVariable Long id, Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        return categoryRepository.findByIdAndTenantId(id, user.getTenantId())
                .<ResponseEntity<?>>map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Category not found")));
    }

    @PostMapping
    @PreAuthorize("hasAuthority('menu:manage')")
    public ResponseEntity<?> createCategory(
            @Valid @RequestBody CategoryRequest request, Authentication authentication) {

        User user = branchScope.requireUser(authentication);

        String name = request.getName().trim();

        if (categoryRepository.existsByNameIgnoreCaseAndTenantId(name, user.getTenantId())) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("error", "Category already exists"));
        }

        Category category = new Category();
        category.setName(name);
        category.setTenantId(user.getTenantId());

        Category savedCategory = categoryRepository.save(category);

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(savedCategory);
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('menu:manage')")
    public ResponseEntity<?> updateCategory(
            @PathVariable Long id,
            @Valid @RequestBody CategoryRequest request, Authentication authentication) {

        User user = branchScope.requireUser(authentication);

        return categoryRepository.findByIdAndTenantId(id, user.getTenantId())
                .<ResponseEntity<?>>map(category -> {
                    String name = request.getName().trim();

                    if (categoryRepository.existsByNameIgnoreCaseAndTenantId(name, user.getTenantId())
                            && !category.getName().equalsIgnoreCase(name)) {
                        return ResponseEntity.status(HttpStatus.CONFLICT)
                                .body(Map.of("error", "Category already exists"));
                    }

                    category.setName(name);
                    return ResponseEntity.ok(categoryRepository.save(category));
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Category not found")));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasAuthority('menu:manage')")
    public ResponseEntity<?> deleteCategory(@PathVariable Long id, Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        return categoryRepository.findByIdAndTenantId(id, user.getTenantId())
                .<ResponseEntity<?>>map(category -> {
                    try {
                        categoryRepository.delete(category);
                        categoryRepository.flush();
                        return ResponseEntity.noContent().build();
                    } catch (DataIntegrityViolationException exception) {
                        return ResponseEntity.status(HttpStatus.CONFLICT)
                                .body(Map.of(
                                        "error",
                                        "Category cannot be deleted because it is in use"));
                    }
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Category not found")));
    }
}
