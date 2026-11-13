package com.dinemaster.role;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;
import java.util.List;

public interface RoleRepository extends JpaRepository<Role, Long> {
    Optional<Role> findByCodeAndActiveTrue(String code);
    Optional<Role> findByCodeAndTenantIdAndActiveTrue(String code, Long tenantId);
    Optional<Role> findByCodeAndTenantIdIsNullAndActiveTrue(String code);
    List<Role> findAllByTenantIdIsNullOrTenantIdOrderByCode(Long tenantId);
}
