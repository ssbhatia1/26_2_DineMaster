package com.dinemaster.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
@Table(name = "recipes", uniqueConstraints = @UniqueConstraint(columnNames = { "product_id", "ingredient_id" }))
public class Recipe {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "product_id", nullable = false)
    private Product product;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ingredient_id", nullable = false)
    private InventoryItem ingredient;
    @Column(name = "quantity_used", nullable = false, precision = 12, scale = 3)
    private BigDecimal quantityUsed;

    public Long getId() {
        return id;
    }

    public void setId(Long value) {
        id = value;
    }

    public Product getProduct() {
        return product;
    }

    public void setProduct(Product value) {
        product = value;
    }

    public InventoryItem getIngredient() {
        return ingredient;
    }

    public void setIngredient(InventoryItem value) {
        ingredient = value;
    }

    public BigDecimal getQuantityUsed() {
        return quantityUsed;
    }

    public void setQuantityUsed(BigDecimal value) {
        quantityUsed = value;
    }
}