
package com.dinemaster.controller;

import com.dinemaster.entity.Customer;
import com.dinemaster.repository.CustomerRepository;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/customers")
public class CustomerController {

    private final CustomerRepository customerRepository;

    public CustomerController(CustomerRepository customerRepository) {
        this.customerRepository = customerRepository;
    }

    @GetMapping
    public ResponseEntity<?> getAllCustomers() {
        return ResponseEntity.ok(customerRepository.findAll());
    }

    @GetMapping("/{id}")
    public ResponseEntity<?> getCustomerById(@PathVariable Long id) {
        return customerRepository.findById(id)
                .<ResponseEntity<?>>map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Customer not found")));
    }

    @PostMapping
    public ResponseEntity<?> createCustomer(@RequestBody Customer customer) {
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

        if (customerRepository.existsByPhone(phone)) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("error", "Phone number already exists"));
        }

        customer.setId(null);
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
    public ResponseEntity<?> updateCustomer(
            @PathVariable Long id,
            @RequestBody Customer request) {

        if (request.getName() == null || request.getName().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Customer name is required"));
        }

        if (request.getPhone() == null || request.getPhone().isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Customer phone is required"));
        }

        return customerRepository.findById(id)
                .<ResponseEntity<?>>map(existing -> {
                    String phone = request.getPhone().trim();

                    boolean phoneUsedByAnotherCustomer =
                            customerRepository.findByPhone(phone)
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
    public ResponseEntity<?> deleteCustomer(@PathVariable Long id) {
        if (!customerRepository.existsById(id)) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", "Customer not found"));
        }

        customerRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
