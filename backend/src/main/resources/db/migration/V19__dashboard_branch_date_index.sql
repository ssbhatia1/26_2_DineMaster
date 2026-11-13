CREATE INDEX IF NOT EXISTS idx_orders_branch_time_status
    ON orders (restaurant_id, order_time, status);
