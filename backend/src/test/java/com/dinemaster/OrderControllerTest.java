package com.dinemaster;

import com.dinemaster.entity.Order;
import com.dinemaster.entity.OrderItem;
import com.dinemaster.entity.Product;
import com.dinemaster.entity.Restaurant;
import com.dinemaster.repository.OrderItemRepository;
import com.dinemaster.repository.OrderRepository;
import com.dinemaster.repository.ProductRepository;
import com.dinemaster.repository.RestaurantRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.math.BigDecimal;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class OrderControllerTest {

        @Autowired
        private MockMvc mockMvc;

        @Autowired
        private OrderRepository orderRepository;

        @Autowired
        private OrderItemRepository orderItemRepository;

        @Autowired
        private ProductRepository productRepository;

        @Autowired
        private RestaurantRepository restaurantRepository;

        private Long restaurantId;
        private Long orderId;

        @BeforeEach
        void setUp() {
                orderItemRepository.deleteAllInBatch();
                orderRepository.deleteAllInBatch();
                productRepository.deleteAllInBatch();
                restaurantRepository.deleteAllInBatch();

                Restaurant restaurant = new Restaurant();
                restaurant.setName("Order API Test Restaurant");
                restaurantId = restaurantRepository.saveAndFlush(restaurant).getId();

                Product product = new Product();
                product.setName("Test Pasta");
                product.setPrice(new BigDecimal("12.50"));
                product.setCategory("Main Course");
                product.setVeg(1);
                Product savedProduct = productRepository.saveAndFlush(product);

                Order order = new Order();
                order.setRestaurant(restaurant);
                order.setStatus("Pending");
                order.setType("Dine In");
                order.setTotalAmount(new BigDecimal("25.00"));
                order.setDiscountAmount(BigDecimal.ZERO);
                Order savedOrder = orderRepository.saveAndFlush(order);
                orderId = savedOrder.getId();

                OrderItem item = new OrderItem();
                item.setOrder(savedOrder);
                item.setProduct(savedProduct);
                item.setQuantity(2);
                item.setPrice(savedProduct.getPrice());
                item.setStatus("Pending");
                orderItemRepository.saveAndFlush(item);
        }

        @Test
        @WithMockUser
        void orderEndpointsSerializeLazyRelationshipsWithoutServerError() throws Exception {
                mockMvc.perform(get("/api/orders")
                                .param("restaurantId", restaurantId.toString())
                                .accept(MediaType.APPLICATION_JSON))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$[0].id").value(orderId))
                                .andExpect(jsonPath("$[0].restaurantId").value(restaurantId));

                mockMvc.perform(get("/api/orders/{id}", orderId)
                                .accept(MediaType.APPLICATION_JSON))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$.id").value(orderId))
                                .andExpect(jsonPath("$.totalAmount").value(25.0));

                mockMvc.perform(get("/api/orders/{id}/items", orderId)
                                .accept(MediaType.APPLICATION_JSON))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$[0].product_name").value("Test Pasta"))
                                .andExpect(jsonPath("$[0].quantity").value(2));
        }

        @Test
        @WithMockUser
        void missingOrderAndRestaurantReturnNotFound() throws Exception {
                mockMvc.perform(get("/api/orders")
                                .param("restaurantId", "999999")
                                .accept(MediaType.APPLICATION_JSON))
                                .andExpect(status().isNotFound());

                mockMvc.perform(get("/api/orders/{id}", 999999)
                                .accept(MediaType.APPLICATION_JSON))
                                .andExpect(status().isNotFound());

                mockMvc.perform(get("/api/orders/{id}/items", 999999)
                                .accept(MediaType.APPLICATION_JSON))
                                .andExpect(status().isNotFound());
        }

        @Test
        @WithMockUser
        void orderLifecycleEndpointsPersistStatusAndPayment() throws Exception {
                mockMvc.perform(post("/api/orders/{id}/hold", orderId))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$.status").value("Held"));

                mockMvc.perform(patch("/api/orders/{id}/status", orderId)
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"status\":\"Preparing\"}"))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$.status").value("Preparing"));

                mockMvc.perform(post("/api/orders/{id}/payment", orderId)
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"paymentMethod\":\"UPI\"}"))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$.status").value("Completed"))
                                .andExpect(jsonPath("$.paymentStatus").value("Paid"))
                                .andExpect(jsonPath("$.paymentMethod").value("UPI"));

                mockMvc.perform(post("/api/orders/{id}/cancel", orderId))
                                .andExpect(status().isBadRequest());
        }
}
