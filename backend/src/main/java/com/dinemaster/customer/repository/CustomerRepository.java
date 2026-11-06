package com.dinemaster.customer.repository;




import com.dinemaster.customer.entity.Customer;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.List;

public interface CustomerRepository
        extends JpaRepository<Customer, Long> {

    Optional<Customer> findByPhone(String phone);

    Optional<Customer> findByPhoneAndTenantId(String phone, Long tenantId);

    boolean existsByPhone(String phone);

    boolean existsByPhoneAndTenantId(String phone, Long tenantId);

    List<Customer> findAllByTenantId(Long tenantId);
}
