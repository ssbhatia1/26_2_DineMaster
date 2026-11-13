package com.dinemaster.dashboard;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class DashboardReadRepository {
    private final JdbcTemplate jdbc;

    public DashboardReadRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public RevenueAggregate revenue(Long branchId, OffsetDateTime start, OffsetDateTime end) {
        return jdbc.queryForObject("""
                SELECT COALESCE(SUM(total_amount), 0), COUNT(DISTINCT id)
                FROM orders
                WHERE restaurant_id = ? AND order_time >= ? AND order_time < ?
                  AND UPPER(status) IN ('PAID', 'COMPLETED')
                """, (rs, row) -> new RevenueAggregate(rs.getBigDecimal(1), rs.getLong(2)),
                branchId, start, end);
    }

    public long activeTables(Long branchId) {
        Long count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM tables
                WHERE restaurant_id = ? AND is_active = TRUE
                """, Long.class, branchId);
        return count == null ? 0 : count;
    }

    public long occupiedTables(Long branchId) {
        Long count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM tables
                WHERE restaurant_id = ? AND is_active = TRUE
                  AND UPPER(REPLACE(status, ' ', '_')) NOT IN ('AVAILABLE', 'OUT_OF_SERVICE')
                """, Long.class, branchId);
        return count == null ? 0 : count;
    }

    public long lowStockItems(Long branchId) {
        Long count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM inventory
                WHERE restaurant_id = ? AND current_stock <= low_stock_threshold
                """, Long.class, branchId);
        return count == null ? 0 : count;
    }

    public record RevenueAggregate(BigDecimal amount, long eligibleOrders) { }
}
