ALTER TABLE users
    ADD COLUMN restaurant_id BIGINT REFERENCES restaurants(id);

CREATE INDEX idx_users_restaurant_id
    ON users(restaurant_id);

UPDATE users
SET restaurant_id = (SELECT MIN(id) FROM restaurants)
WHERE restaurant_id IS NULL
  AND (SELECT COUNT(*) FROM restaurants) = 1;
