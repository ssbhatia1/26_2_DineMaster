package com.dinemaster;

import com.dinemaster.entity.Category;
import com.dinemaster.entity.Product;
import com.dinemaster.repository.CategoryRepository;
import com.dinemaster.repository.OrderItemRepository;
import com.dinemaster.repository.ProductRepository;
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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class ProductControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ProductRepository productRepository;

    @Autowired
    private OrderItemRepository orderItemRepository;

    @Autowired
    private CategoryRepository categoryRepository;

    @BeforeEach
    void setUp() {
        orderItemRepository.deleteAllInBatch();
        productRepository.deleteAllInBatch();
        categoryRepository.deleteAllInBatch();

        Category category = new Category();
        category.setName("Starters");
        categoryRepository.saveAndFlush(category);

        Product product = new Product();
        product.setName("Egg Roll");
        product.setPrice(new BigDecimal("120.00"));
        product.setCategory("Starters");
        product.setVeg(2);
        productRepository.saveAndFlush(product);
    }

    @Test
    @WithMockUser
    void productResponsePreservesFoodTypeAndAvailabilityContract() throws Exception {
        mockMvc.perform(get("/api/products").accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].is_veg").value(2))
                .andExpect(jsonPath("$[0].is_available").value(true));
    }

    @Test
    @WithMockUser
    void productRejectsUnsupportedFoodType() throws Exception {
        mockMvc.perform(post("/api/products")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "name": "Invalid Food Type",
                          "price": 100.00,
                          "category": "Starters",
                          "is_veg": 4
                        }
                        """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("is_veg must be one of 0, 1, 2, or 3"));
    }
}