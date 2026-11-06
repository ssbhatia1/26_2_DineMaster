ALTER TABLE products
    ALTER COLUMN is_veg TYPE SMALLINT
    USING CASE WHEN is_veg THEN 1 ELSE 0 END;

ALTER TABLE products
    ADD CONSTRAINT products_is_veg_check CHECK (is_veg BETWEEN 0 AND 3);