package com.dinemaster.user.repository;




import com.dinemaster.user.entity.User;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.jpa.repository.Lock;
import jakarta.persistence.LockModeType;

import java.util.Optional;
import java.util.List;

public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByUsername(String username);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select user from User user where user.username = :username")
    Optional<User> findForAuthenticationByUsername(@Param("username") String username);

    boolean existsByUsername(String username);

    List<User> findAllByRoleIgnoreCase(String role);

    List<User> findAllByTenantId(Long tenantId);

    @Query(value = "select count(*) from users where upper(role) = upper(:role) and is_active = true", nativeQuery = true)
    long countActiveByRole(@Param("role") String role);

    @Query(value = "select count(*) from users where (upper(role) = upper(:role) or (:role = 'OWNER' and upper(role) in ('ADMIN','RESTAURANT_ADMIN'))) and tenant_id = :tenantId and is_active = true", nativeQuery = true)
    long countActiveByRoleAndTenantId(@Param("role") String role, @Param("tenantId") Long tenantId);
}
