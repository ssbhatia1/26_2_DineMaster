package com.dinemaster.qr.dto;

import java.time.OffsetDateTime;
import java.util.List;

public record GuestOrderResponse(Long id, String status, OffsetDateTime orderTime, List<Item> items) {
    public record Item(String name, Integer quantity) {}
}
