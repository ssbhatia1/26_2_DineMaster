package com.dinemaster.catalog.repository;




import com.dinemaster.catalog.entity.Category;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.List;

public interface CategoryRepository
        extends JpaRepository<Category, Long> {

    Optional<Category> findByName(String name);

    boolean existsByName(String name);

    List<Category> findAllByTenantId(Long tenantId);

    Optional<Category> findByIdAndTenantId(Long id, Long tenantId);

    boolean existsByNameIgnoreCaseAndTenantId(String name, Long tenantId);

    Optional<Category> findFirstByNameIgnoreCaseAndTenantId(String name, Long tenantId);
}
