package com.dinemaster.booking.controller;



import com.dinemaster.booking.dto.BookingRequest;
import com.dinemaster.booking.entity.Booking;
import com.dinemaster.booking.repository.BookingRepository;
import com.dinemaster.customer.entity.Customer;
import com.dinemaster.customer.repository.CustomerRepository;
import com.dinemaster.diningtable.entity.DiningTable;
import com.dinemaster.diningtable.repository.DiningTableRepository;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.restaurant.repository.RestaurantRepository;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/reservations")
public class BookingController {
    private final BookingRepository bookingRepository;
    private final RestaurantRepository restaurantRepository;
    private final DiningTableRepository tableRepository;
    private final CustomerRepository customerRepository;

    public BookingController(BookingRepository bookingRepository, RestaurantRepository restaurantRepository,
            DiningTableRepository tableRepository, CustomerRepository customerRepository) {
        this.bookingRepository = bookingRepository;
        this.restaurantRepository = restaurantRepository;
        this.tableRepository = tableRepository;
        this.customerRepository = customerRepository;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('reservation:view')")
    public List<Booking> list(@RequestParam Long restaurantId) {
        return bookingRepository.findByRestaurant_IdOrderByBookingTimeAsc(restaurantId);
    }

    @PostMapping
    @PreAuthorize("hasAuthority('reservation:create')")
    @Transactional
    public ResponseEntity<?> create(@Valid @RequestBody BookingRequest request) {
        Values values = resolve(request).orElse(null);
        if (values == null)
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid restaurant, table, or customer"));
        Booking booking = new Booking();
        copy(request, booking, values.restaurant(), values.table(), values.customer());
        return ResponseEntity.status(HttpStatus.CREATED).body(bookingRepository.save(booking));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('reservation:update')")
    @Transactional
    public ResponseEntity<?> update(@PathVariable Long id, @Valid @RequestBody BookingRequest request) {
        return bookingRepository.findById(id).flatMap(existing -> resolve(request).map(values -> {
            copy(request, existing, values.restaurant(), values.table(), values.customer());
            return (ResponseEntity<?>) ResponseEntity.ok(bookingRepository.save(existing));
        })).orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PatchMapping("/{id}/status")
    @PreAuthorize("hasAuthority('reservation:update')")
    @Transactional
    public ResponseEntity<?> status(@PathVariable Long id, @RequestParam String value) {
        if (value == null || !List.of("Pending", "Confirmed", "Cancelled", "Completed").contains(value)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid booking status"));
        }
        return bookingRepository.findById(id).map(booking -> {
            booking.setStatus(value);
            return ResponseEntity.ok(bookingRepository.save(booking));
        }).orElseGet(() -> ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasAuthority('reservation:update')")
    public ResponseEntity<?> delete(@PathVariable Long id) {
        if (!bookingRepository.existsById(id))
            return ResponseEntity.notFound().build();
        bookingRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    private java.util.Optional<Values> resolve(BookingRequest request) {
        return restaurantRepository.findById(request.restaurantId())
                .flatMap(
                        restaurant -> tableRepository.findById(request.tableId())
                                .filter(table -> table.getRestaurant() != null
                                        && request.restaurantId().equals(table.getRestaurant().getId()))
                                .flatMap(table -> {
                                    if (request.customerId() == null)
                                        return java.util.Optional.of(new Values(restaurant, table, null));
                                    return customerRepository.findById(request.customerId())
                                            .filter(customer -> restaurant.getTenantId().equals(customer.getTenantId()))
                                            .map(customer -> new Values(restaurant, table, customer));
                                }));
    }

    private void copy(BookingRequest request, Booking booking, Restaurant restaurant, DiningTable table,
            Customer customer) {
        booking.setRestaurant(restaurant);
        booking.setTable(table);
        booking.setCustomer(customer);
        booking.setCustomerName(request.customerName());
        booking.setCustomerPhone(request.customerPhone());
        booking.setGuestCount(request.guestCount());
        booking.setBookingTime(request.bookingTime());
        booking.setStatus(request.status() == null ? "Pending" : request.status());
        booking.setNotes(request.notes());
    }

    private record Values(Restaurant restaurant, DiningTable table, Customer customer) {
    }
}
