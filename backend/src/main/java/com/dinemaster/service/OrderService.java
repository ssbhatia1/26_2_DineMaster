
package com.dinemaster.service;

import com.dinemaster.dto.CreateOrderRequest;
import com.dinemaster.dto.OrderItemRequest;
import com.dinemaster.dto.OrderItemResponse;
import com.dinemaster.dto.OrderResponse;
import com.dinemaster.dto.OrderStatusRequest;
import com.dinemaster.dto.PaymentRequest;
import com.dinemaster.entity.*;
import com.dinemaster.repository.*;
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
                        "Completed", "Held", "Cancelled");

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
        public OrderResponse updateStatus(Long orderId, OrderStatusRequest request) {
                String status = request.status().trim();
                if (!ALLOWED_STATUSES.contains(status)) {
                        throw new ResponseStatusException(
                                        HttpStatus.BAD_REQUEST, "Unsupported order status: " + status);
                }
                Order order = findOrder(orderId);
                order.setStatus(status);
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
                return OrderResponse.from(orderRepository.save(order));
        }

        private Order findOrder(Long orderId) {
                return orderRepository.findById(orderId)
                                .orElseThrow(() -> new ResponseStatusException(
                                                HttpStatus.NOT_FOUND, "Order not found"));
        }
}
