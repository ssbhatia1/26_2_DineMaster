package com.dinemaster.qr.dto;

import java.math.BigDecimal;
import java.util.List;

public record GuestMenuResponse(String tableLabel, List<Item> items) {
    public record Item(Long id, String name, String description, String category,
                       BigDecimal price, String imagePath, Integer veg) {}
}
