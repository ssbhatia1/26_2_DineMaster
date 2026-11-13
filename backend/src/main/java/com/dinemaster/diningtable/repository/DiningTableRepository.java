package com.dinemaster.diningtable.repository;





import com.dinemaster.diningtable.entity.DiningTable;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.restaurant.entity.Restaurant;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

import java.util.List;
import java.util.Optional;

public interface DiningTableRepository
        extends JpaRepository<DiningTable, Long> {

    List<DiningTable> findByStatus(String status);

    boolean existsByRestaurant_IdAndTableNumber(Long restaurantId, String tableNumber);

    List<DiningTable> findByRestaurant_IdOrderByTableNumberAsc(Long restaurantId);

    List<DiningTable> findAllByRestaurant_IdAndFloorIdAndActiveTrueOrderByTableNumberAsc(Long restaurantId, Long floorId);

    List<DiningTable> findAllByRestaurant_IdAndStatusIgnoreCaseAndActiveTrueOrderByTableNumberAsc(
            Long restaurantId, String status);

    List<DiningTable> findAllByRestaurant_IdAndActiveTrueOrderByTableNumberAsc(Long restaurantId);

    Optional<DiningTable> findByIdAndRestaurant_Id(Long id, Long restaurantId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from DiningTable t where t.id = :id")
    Optional<DiningTable> findForUpdateById(@Param("id") Long id);
}
