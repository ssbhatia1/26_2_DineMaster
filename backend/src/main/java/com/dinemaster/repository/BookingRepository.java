package com.dinemaster.repository;

import com.dinemaster.entity.Booking;
import org.springframework.data.jpa.repository.JpaRepository;
import java.time.OffsetDateTime;
import java.util.List;

public interface BookingRepository extends JpaRepository<Booking, Long> {
    List<Booking> findByRestaurant_IdOrderByBookingTimeAsc(Long restaurantId);

    List<Booking> findByTable_IdAndBookingTimeBetweenOrderByBookingTimeAsc(Long tableId, OffsetDateTime from,
            OffsetDateTime to);
}