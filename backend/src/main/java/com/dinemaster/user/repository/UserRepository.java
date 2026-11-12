package com.dinemaster.user.repository;




import com.dinemaster.user.entity.User;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.jpa.repository.Lock;
import jakarta.persistence.LockModeType;

import java.util.Optional;
import java.util.List;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByUsername(String username);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select user from User user where user.username = :username")
    Optional<User> findForAuthenticationByUsername(@Param("username") String username);

    boolean existsByUsername(String username);

    List<User> findAllByRoleIgnoreCase(String role);

    List<User> findAllByTenantId(Long tenantId);

    @Query(value = """
            select u.* from users u
            where u.tenant_id = :tenantId
              and (:role is null or upper(u.role) = upper(:role))
              and (:active is null or u.is_active = :active)
              and (:branchId is null or exists (
                    select 1 from user_branches ub
                    where ub.user_id = u.id and ub.branch_id = :branchId))
              and (:query is null or lower(u.name) like lower(concat('%', :query, '%'))
                    or lower(u.username) like lower(concat('%', :query, '%'))
                    or lower(coalesce(u.contact_details, '')) like lower(concat('%', :query, '%')))
            """,
            countQuery = """
            select count(*) from users u
            where u.tenant_id = :tenantId
              and (:role is null or upper(u.role) = upper(:role))
              and (:active is null or u.is_active = :active)
              and (:branchId is null or exists (
                    select 1 from user_branches ub
                    where ub.user_id = u.id and ub.branch_id = :branchId))
              and (:query is null or lower(u.name) like lower(concat('%', :query, '%'))
                    or lower(u.username) like lower(concat('%', :query, '%'))
                    or lower(coalesce(u.contact_details, '')) like lower(concat('%', :query, '%')))
            """, nativeQuery = true)
    Page<User> searchTenantUsers(@Param("tenantId") Long tenantId,
            @Param("role") String role, @Param("active") Boolean active,
            @Param("branchId") Long branchId, @Param("query") String query, Pageable pageable);

    @Query(value = """
            select u.* from users u
            where u.tenant_id = :tenantId
              and upper(u.role) in ('CASHIER', 'WAITER', 'CHEF', 'INVENTORY_MANAGER', 'STAFF')
              and exists (select 1 from user_branches scoped
                          where scoped.user_id = u.id and scoped.branch_id in (:visibleBranches))
              and (:role is null or upper(u.role) = upper(:role))
              and (:active is null or u.is_active = :active)
              and (:branchId is null or exists (
                    select 1 from user_branches ub
                    where ub.user_id = u.id and ub.branch_id = :branchId))
              and (:query is null or lower(u.name) like lower(concat('%', :query, '%'))
                    or lower(u.username) like lower(concat('%', :query, '%'))
                    or lower(coalesce(u.contact_details, '')) like lower(concat('%', :query, '%')))
            """,
            countQuery = """
            select count(*) from users u
            where u.tenant_id = :tenantId
              and upper(u.role) in ('CASHIER', 'WAITER', 'CHEF', 'INVENTORY_MANAGER', 'STAFF')
              and exists (select 1 from user_branches scoped
                          where scoped.user_id = u.id and scoped.branch_id in (:visibleBranches))
              and (:role is null or upper(u.role) = upper(:role))
              and (:active is null or u.is_active = :active)
              and (:branchId is null or exists (
                    select 1 from user_branches ub
                    where ub.user_id = u.id and ub.branch_id = :branchId))
              and (:query is null or lower(u.name) like lower(concat('%', :query, '%'))
                    or lower(u.username) like lower(concat('%', :query, '%'))
                    or lower(coalesce(u.contact_details, '')) like lower(concat('%', :query, '%')))
            """, nativeQuery = true)
    Page<User> searchTenantUsersInBranches(@Param("tenantId") Long tenantId,
            @Param("visibleBranches") List<Long> visibleBranches, @Param("role") String role,
            @Param("active") Boolean active, @Param("branchId") Long branchId,
            @Param("query") String query, Pageable pageable);

    @Query(value = "select count(*) from users where upper(role) = upper(:role) and is_active = true", nativeQuery = true)
    long countActiveByRole(@Param("role") String role);

    @Query(value = "select count(*) from users where (upper(role) = upper(:role) or (:role = 'OWNER' and upper(role) in ('ADMIN','RESTAURANT_ADMIN'))) and tenant_id = :tenantId and is_active = true", nativeQuery = true)
    long countActiveByRoleAndTenantId(@Param("role") String role, @Param("tenantId") Long tenantId);
}
