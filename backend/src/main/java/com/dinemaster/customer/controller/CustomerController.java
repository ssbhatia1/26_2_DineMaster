package com.dinemaster.customer.controller;




import com.dinemaster.customer.entity.Customer;
import com.dinemaster.customer.repository.CustomerRepository;
import com.dinemaster.security.BranchScopeService;
import com.dinemaster.user.entity.User;
import jakarta.validation.Valid;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/customers")
public class CustomerController {

    private final CustomerRepository customerRepository;
    private final BranchScopeService branchScope;

    public CustomerController(CustomerRepository customerRepository, BranchScopeService branchScope) {
        this.customerRepository = customerRepository;
        this.branchScope = branchScope;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('customer:view')")
    public ResponseEntity<?> getAllCustomers(Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        return ResponseEntity.ok(customerRepository.findAllByTenantId(user.getTenantId()));
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('customer:view')")
    public ResponseEntity<?> getCustomerById(@PathVariable Long id, Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        return customerRepository.findById(id).filter(customer -> customer.getTenantId().equals(user.getTenantId()))
                .<ResponseEntity<?>>map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Customer not found")));
    }

    @PostMapping
    @PreAuthorize("hasAuthority('customer:manage')")
    public ResponseEntity<?> createCustomer(@Valid @RequestBody Customer customer, Authentication authentication) {
        if (customer == null || customer.getName() == null
                || customer.getName().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Customer name is required"));
        }

        if (customer.getPhone() == null || customer.getPhone().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Customer phone is required"));
        }

        String phone = customer.getPhone().trim();
        User user = branchScope.requireUser(authentication);

        if (customerRepository.existsByPhoneAndTenantId(phone, user.getTenantId())) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("error", "Phone number already exists"));
        }

        customer.setId(null);
        customer.setTenantId(user.getTenantId());
        customer.setName(customer.getName().trim());
        customer.setPhone(phone);
        customer.setEmail(customer.getEmail() == null
                ? null : customer.getEmail().trim());
        customer.setLoyaltyPoints(0);
        customer.setCreatedAt(null);

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(customerRepository.save(customer));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('customer:manage')")
    public ResponseEntity<?> updateCustomer(
            @PathVariable Long id,
            @Valid @RequestBody Customer request, Authentication authentication) {

        if (request.getName() == null || request.getName().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Customer name is required"));
        }

        if (request.getPhone() == null || request.getPhone().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Customer phone is required"));
        }

        User user = branchScope.requireUser(authentication);
        return customerRepository.findById(id).filter(customer -> customer.getTenantId().equals(user.getTenantId()))
                .<ResponseEntity<?>>map(existing -> {
                    String phone = request.getPhone().trim();

                    boolean phoneUsedByAnotherCustomer =
                            customerRepository.findByPhoneAndTenantId(phone, user.getTenantId())
                                    .filter(found -> !found.getId().equals(id))
                                    .isPresent();

                    if (phoneUsedByAnotherCustomer) {
                        return ResponseEntity.status(HttpStatus.CONFLICT)
                                .body(Map.of("error",
                                        "Phone number already exists"));
                    }

                    existing.setName(request.getName().trim());
                    existing.setPhone(phone);
                    existing.setEmail(request.getEmail() == null
                            ? null : request.getEmail().trim());

                    return ResponseEntity.ok(
                            customerRepository.save(existing));
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Customer not found")));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasAuthority('customer:manage')")
    public ResponseEntity<?> deleteCustomer(@PathVariable Long id, Authentication authentication) {
        User user = branchScope.requireUser(authentication);
        if (customerRepository.findById(id).filter(customer -> customer.getTenantId().equals(user.getTenantId())).isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "Customer not found"));
        }
        if (!customerRepository.existsById(id)) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", "Customer not found"));
        }

        customerRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
