package com.dinemaster.orders.service;
import com.dinemaster.orders.dto.AddOrderItemsRequest;
import com.dinemaster.orders.dto.CreateOrderRequest;
import com.dinemaster.orders.dto.OrderItemRequest;
import com.dinemaster.orders.dto.OrderItemResponse;
import com.dinemaster.orders.dto.OrderResponse;
import com.dinemaster.orders.dto.OrderStatusRequest;
import com.dinemaster.orders.dto.PaymentRequest;
import com.dinemaster.customer.entity.Customer;
import com.dinemaster.diningtable.entity.DiningTable;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.orders.entity.OrderItem;
import com.dinemaster.catalog.entity.Product;
import com.dinemaster.restaurant.entity.Restaurant;
import com.dinemaster.user.entity.User;
import com.dinemaster.customer.repository.CustomerRepository;
import com.dinemaster.diningtable.repository.DiningTableRepository;
import com.dinemaster.orders.repository.OrderItemRepository;
import com.dinemaster.orders.repository.OrderRepository;
import com.dinemaster.catalog.repository.ProductRepository;
import com.dinemaster.restaurant.repository.RestaurantRepository;
import com.dinemaster.user.repository.UserRepository;
import com.dinemaster.role.Roles;


import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

@Service
public class OrderService {

        private static final Set<String> ALLOWED_STATUSES = Set.of(
                        "Pending", "Received", "Preparing", "Ready", "Served",
                "Billing Pending", "Completed", "Held", "Cancelled");

        private final OrderRepository orderRepository;
        private final OrderItemRepository orderItemRepository;
        private final ProductRepository productRepository;
        private final RestaurantRepository restaurantRepository;
        private final DiningTableRepository diningTableRepository;
        private final CustomerRepository customerRepository;
        private final UserRepository userRepository;

        public OrderService(
                        OrderRepository orderRepository,
                        OrderItemRepository orderItemRepository,
                        ProductRepository productRepository,
                        RestaurantRepository restaurantRepository,
                        DiningTableRepository diningTableRepository,
                        CustomerRepository customerRepository,
                        UserRepository userRepository) {
                this.orderRepository = orderRepository;
                this.orderItemRepository = orderItemRepository;
                this.productRepository = productRepository;
                this.restaurantRepository = restaurantRepository;
                this.diningTableRepository = diningTableRepository;
                this.customerRepository = customerRepository;
                this.userRepository = userRepository;
        }

        @Transactional
        public OrderResponse createOrder(CreateOrderRequest request) {

                Restaurant restaurant = restaurantRepository
                                .findById(request.getRestaurantId())
                                .orElseThrow(() -> new ResponseStatusException(
                                                HttpStatus.NOT_FOUND, "Restaurant not found"));

                Order order = new Order();
                order.setRestaurant(restaurant);
                order.setStatus("Pending");
                order.setType(request.getType() == null
                                || request.getType().isBlank()
                                                ? "Dine In"
                                                : request.getType().trim());
                order.setNotes(request.getNotes());
                order.setGuestCount(request.getGuestCount());

                if (request.getTableId() != null) {
                        DiningTable table = diningTableRepository
                                        .findById(request.getTableId())
                                        .orElseThrow(() -> new ResponseStatusException(
                                                        HttpStatus.NOT_FOUND, "Table not found"));

                        if (table.getRestaurant() == null
                                        || !restaurant.getId().equals(table.getRestaurant().getId())) {
                                throw new ResponseStatusException(
                                                HttpStatus.BAD_REQUEST,
                                                "Table does not belong to this restaurant");
                        }

                        if (!table.isActive()) {
                                throw new ResponseStatusException(
                                                HttpStatus.BAD_REQUEST, "Table is inactive");
                        }
                        if (orderRepository
                                        .findByRestaurant_IdAndDiningTable_IdAndPaymentStatusNot(
                                                        restaurant.getId(), table.getId(), "Paid")
                                        .stream()
                                        .anyMatch(existing -> !Set.of("Completed", "Cancelled")
                                                        .contains(existing.getStatus()))) {
                                throw new ResponseStatusException(
                                                HttpStatus.CONFLICT,
                                                "An active order already exists for this table");
                        }
                        order.setDiningTable(table);
                }

                if (request.getCustomerId() != null) {
                        Customer customer = customerRepository
                                        .findById(request.getCustomerId())
                                        .orElseThrow(() -> new ResponseStatusException(
                                                        HttpStatus.NOT_FOUND, "Customer not found"));
                        order.setCustomer(customer);
                        order.setCustomerName(customer.getName());
                        order.setCustomerPhone(customer.getPhone());
                }

                if (request.getWaiterId() != null) {
                        User waiter = userRepository
                                        .findById(request.getWaiterId())
                                        .orElseThrow(() -> new ResponseStatusException(
                                                        HttpStatus.NOT_FOUND, "Waiter not found"));
                        if (!waiter.isActive() || !Set.of("WAITER", "MANAGER", "OWNER")
                                        .contains(com.dinemaster.role.Roles.canonical(waiter.getRole()))) {
                                throw new ResponseStatusException(
                                                HttpStatus.BAD_REQUEST, "Selected waiter is not assignable");
                        }
                        if (waiter.getRestaurant() != null
                                        && !restaurant.getId().equals(waiter.getRestaurant().getId())) {
                                throw new ResponseStatusException(
                                                HttpStatus.BAD_REQUEST,
                                                "Waiter does not belong to this restaurant");
                        }
                        order.setWaiter(waiter);
                        order.setOrderTaker(waiter.getName());
                }

                BigDecimal subtotal = BigDecimal.ZERO;
                List<OrderItem> items = new ArrayList<>();

                for (OrderItemRequest itemRequest : request.getItems()) {
                        Product product = productRepository
                                        .findById(itemRequest.getProductId())
                                        .orElseThrow(() -> new ResponseStatusException(
                                                        HttpStatus.NOT_FOUND,
                                                        "Product not found: " + itemRequest.getProductId()));
                        if (product.getRestaurant() == null
                                        || !restaurant.getId().equals(product.getRestaurant().getId())) {
                                throw new ResponseStatusException(
                                                HttpStatus.BAD_REQUEST,
                                                "Product does not belong to this restaurant");
                        }

                        if (!product.isAvailable()) {
                                throw new ResponseStatusException(
                                                HttpStatus.BAD_REQUEST,
                                                "Product is unavailable: " + product.getName());
                        }

                        BigDecimal lineTotal = product.getPrice().multiply(
                                        BigDecimal.valueOf(itemRequest.getQuantity()));

                        subtotal = subtotal.add(lineTotal);

                        OrderItem item = new OrderItem();
                        item.setOrder(order);
                        item.setProduct(product);
                        item.setQuantity(itemRequest.getQuantity());
                        item.setPrice(product.getPrice());
                        item.setNotes(itemRequest.getNotes());
                        item.setStatus("Pending");

                        items.add(item);
                }

                BigDecimal discount = request.getDiscountAmount() == null
                                ? BigDecimal.ZERO
                                : request.getDiscountAmount();

                if (discount.compareTo(BigDecimal.ZERO) < 0
                                || discount.compareTo(subtotal) > 0) {
                        throw new ResponseStatusException(
                                        HttpStatus.BAD_REQUEST,
                                        "Discount must be between zero and the subtotal");
                }

                order.setDiscountAmount(discount);
                order.setTotalAmount(subtotal.subtract(discount));
                if (order.getDiningTable() != null) {
                        order.getDiningTable().setStatus("Occupied");
                        diningTableRepository.save(order.getDiningTable());
                }

                Order savedOrder = orderRepository.saveAndFlush(order);

                for (OrderItem item : items) {
                        item.setOrder(savedOrder);
                }

                orderItemRepository.saveAll(items);

                return OrderResponse.from(savedOrder);
        }

        @Transactional(readOnly = true)
        public List<OrderResponse> getOrdersByRestaurant(Long restaurantId) {
                if (!restaurantRepository.existsById(restaurantId)) {
                        throw new ResponseStatusException(
                                        HttpStatus.NOT_FOUND, "Restaurant not found");
                }

                return orderRepository
                                .findByRestaurant_IdOrderByOrderTimeDesc(restaurantId)
                                .stream()
                                .map(OrderResponse::from)
                                .toList();
        }

        @Transactional(readOnly = true)
        public OrderResponse getOrderById(Long orderId) {
                Order order = orderRepository.findById(orderId)
                                .orElseThrow(() -> new ResponseStatusException(
                                                HttpStatus.NOT_FOUND, "Order not found"));
                return OrderResponse.from(order);
        }

        @Transactional(readOnly = true)
        public List<OrderItemResponse> getOrderItems(Long orderId) {
                if (!orderRepository.existsById(orderId)) {
                        throw new ResponseStatusException(
                                        HttpStatus.NOT_FOUND, "Order not found");
                }

                return orderItemRepository.findByOrder_Id(orderId)
                                .stream()
                                .map(OrderItemResponse::from)
                                .toList();
        }

        @Transactional
        public OrderResponse addItems(Long orderId, AddOrderItemsRequest request) {
                Order order = findOrder(orderId);
                if ("Cancelled".equalsIgnoreCase(order.getStatus())
                                || "Completed".equalsIgnoreCase(order.getStatus())) {
                        throw new ResponseStatusException(
                                        HttpStatus.BAD_REQUEST,
                                        "Items cannot be added to a completed or cancelled order");
                }

                BigDecimal additionalTotal = BigDecimal.ZERO;
                List<OrderItem> items = new ArrayList<>();
                for (OrderItemRequest itemRequest : request.getItems()) {
                        Product product = productRepository.findById(itemRequest.getProductId())
                                        .orElseThrow(() -> new ResponseStatusException(
                                                        HttpStatus.NOT_FOUND,
                                                        "Product not found: " + itemRequest.getProductId()));
                        if (product.getRestaurant() == null
                                                        || order.getRestaurant() == null
                                                        || !order.getRestaurant().getId().equals(product.getRestaurant().getId())) {
                                throw new ResponseStatusException(
                                                                HttpStatus.BAD_REQUEST,
                                                                "Product does not belong to this restaurant");
                        }
                        if (!product.isAvailable()) {
                                throw new ResponseStatusException(
                                                HttpStatus.BAD_REQUEST,
                                                "Product is unavailable: " + product.getName());
                        }

                        additionalTotal = additionalTotal.add(product.getPrice()
                                        .multiply(BigDecimal.valueOf(itemRequest.getQuantity())));

                        OrderItem item = new OrderItem();
                        item.setOrder(order);
                        item.setProduct(product);
                        item.setQuantity(itemRequest.getQuantity());
                        item.setPrice(product.getPrice());
                        item.setNotes(itemRequest.getNotes());
                        item.setStatus("Pending");
                        items.add(item);
                }

                orderItemRepository.saveAll(items);
                order.setTotalAmount(order.getTotalAmount().add(additionalTotal));
                if ("Held".equalsIgnoreCase(order.getStatus())) {
                        order.setStatus("Pending");
                }
                return OrderResponse.from(orderRepository.save(order));
        }

        @Transactional
        public OrderResponse updateStatus(Long orderId, OrderStatusRequest request) {
                String status = request.status().trim();
                if (!ALLOWED_STATUSES.contains(status)) {
                        throw new ResponseStatusException(
                                        HttpStatus.BAD_REQUEST, "Unsupported order status: " + status);
                }
                Order order = findOrder(orderId);
                String currentStatus = order.getStatus();
                if (!isValidTransition(currentStatus, status)) {
                        throw new ResponseStatusException(
                                        HttpStatus.BAD_REQUEST,
                                        "Cannot change order status from " + currentStatus + " to " + status);
                }
                order.setStatus(status);
                synchronizeTableStatus(order);
                return OrderResponse.from(orderRepository.save(order));
        }

        @Transactional
        public OrderResponse hold(Long orderId) {
                Order order = findOrder(orderId);
                order.setStatus("Held");
                return OrderResponse.from(orderRepository.save(order));
        }

        @Transactional
        public OrderResponse cancel(Long orderId) {
                Order order = findOrder(orderId);
                if ("Paid".equalsIgnoreCase(order.getPaymentStatus())) {
                        throw new ResponseStatusException(
                                        HttpStatus.BAD_REQUEST, "A paid order cannot be cancelled");
                }
                order.setStatus("Cancelled");
                synchronizeTableStatus(order);
                return OrderResponse.from(orderRepository.save(order));
        }

        @Transactional
        public OrderResponse recordPayment(Long orderId, PaymentRequest request) {
                String paymentMethod = request.paymentMethod().trim();
                if (paymentMethod.length() > 50) {
                        throw new ResponseStatusException(
                                        HttpStatus.BAD_REQUEST, "Payment method cannot exceed 50 characters");
                }
                Order order = findOrder(orderId);
                if ("Cancelled".equalsIgnoreCase(order.getStatus())) {
                        throw new ResponseStatusException(
                                        HttpStatus.BAD_REQUEST, "A cancelled order cannot be paid");
                }
                order.setPaymentStatus("Paid");
                order.setPaymentMethod(paymentMethod);
                order.setStatus("Completed");
                synchronizeTableStatus(order);
                return OrderResponse.from(orderRepository.save(order));
        }

        private boolean isValidTransition(String current, String target) {
                if (current.equals(target)) {
                        return true;
                }
                return switch (current) {
                        case "Pending" -> Set.of("Received", "Cancelled").contains(target);
                        case "Held" -> Set.of("Received", "Preparing", "Cancelled").contains(target);
                        case "Received" -> Set.of("Preparing", "Cancelled").contains(target);
                        case "Preparing" -> Set.of("Ready", "Cancelled").contains(target);
                        case "Ready" -> Set.of("Served", "Cancelled").contains(target);
                        case "Served" -> Set.of("Billing Pending", "Completed").contains(target);
                        case "Billing Pending" -> Set.of("Completed", "Cancelled").contains(target);
                        default -> false;
                };
        }

        private void synchronizeTableStatus(Order order) {
                DiningTable table = order.getDiningTable();
                if (table == null) {
                        return;
                }
                boolean activeOrderExists = orderRepository
                                .findByRestaurant_IdAndDiningTable_IdAndPaymentStatusNot(
                                                order.getRestaurant().getId(), table.getId(), "Paid")
                                .stream()
                                .anyMatch(other -> !other.getId().equals(order.getId())
                                                && !Set.of("Completed", "Cancelled").contains(other.getStatus()));
                table.setStatus(activeOrderExists ? "Occupied" : "Available");
                diningTableRepository.save(table);
        }

        private Order findOrder(Long orderId) {
                return orderRepository.findById(orderId)
                                .orElseThrow(() -> new ResponseStatusException(
                                                HttpStatus.NOT_FOUND, "Order not found"));
        }
}
