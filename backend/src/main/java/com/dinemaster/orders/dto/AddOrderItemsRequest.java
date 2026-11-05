package com.dinemaster.orders.dto;
import com.dinemaster.orders.entity.Order;


import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;

import java.util.ArrayList;
import java.util.List;

public class AddOrderItemsRequest {

    @Valid
    @NotEmpty(message = "At least one order item is required")
    private List<OrderItemRequest> items = new ArrayList<>();

    public List<OrderItemRequest> getItems() {
        return items;
    }

    public void setItems(List<OrderItemRequest> items) {
        this.items = items;
    }
}
