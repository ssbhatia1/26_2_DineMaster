package com.dinemaster.qr.service;

import com.dinemaster.catalog.entity.Product;
import com.dinemaster.catalog.repository.ProductRepository;
import com.dinemaster.orders.entity.Order;
import com.dinemaster.orders.entity.OrderItem;
import com.dinemaster.orders.repository.OrderItemRepository;
import com.dinemaster.orders.repository.OrderRepository;
import com.dinemaster.qr.dto.GuestMenuResponse;
import com.dinemaster.qr.dto.GuestOrderRequest;
import com.dinemaster.qr.dto.GuestOrderResponse;
import com.dinemaster.qr.entity.GuestServiceRequest;
import com.dinemaster.qr.entity.QrOrderIdempotency;
import com.dinemaster.qr.entity.TableSession;
import com.dinemaster.qr.repository.GuestServiceRequestRepository;
import com.dinemaster.qr.repository.QrOrderIdempotencyRepository;
import com.dinemaster.qr.repository.TableSessionRepository;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class GuestOrderingService {
    private final TableSessionService tokenService;
    private final TableSessionRepository sessions;
    private final ProductRepository products;
    private final OrderRepository orders;
    private final OrderItemRepository orderItems;
    private final QrOrderIdempotencyRepository idempotencies;
    private final GuestServiceRequestRepository serviceRequests;

    public GuestOrderingService(TableSessionService tokenService, TableSessionRepository sessions,
            ProductRepository products, OrderRepository orders, OrderItemRepository orderItems,
            QrOrderIdempotencyRepository idempotencies, GuestServiceRequestRepository serviceRequests) {
        this.tokenService = tokenService;
        this.sessions = sessions;
        this.products = products;
        this.orders = orders;
        this.orderItems = orderItems;
        this.idempotencies = idempotencies;
        this.serviceRequests = serviceRequests;
    }

    @Transactional(readOnly = true)
    public GuestMenuResponse menu(String token) {
        TableSession session = tokenService.resolve(token);
        Long branchId = session.getBranch().getId();
        List<GuestMenuResponse.Item> items = products.findByRestaurant_IdAndAvailableTrue(branchId).stream()
                .map(p -> new GuestMenuResponse.Item(p.getId(), p.getName(), p.getDescription(),
                        p.getCategory(), p.getPrice(), p.getImagePath(), p.getVeg())).toList();
        return new GuestMenuResponse(session.getTable().getTableNumber(), items);
    }

    @Transactional
    public GuestOrderResponse submit(String token, String key, GuestOrderRequest request) {
        if (key == null || key.isBlank() || key.length() > 100) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "A valid Idempotency-Key is required");
        }
        TableSession session = tokenService.lockAndResolve(token);
        var previous = idempotencies.findBySession_IdAndIdempotencyKey(session.getId(), key);
        if (previous.isPresent()) return guestOrder(previous.get().getOrder());
        int totalQuantity = request.items().stream().mapToInt(GuestOrderRequest.Item::quantity).sum();
        if (totalQuantity > 20) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "An order cannot contain more than 20 items in total");
        }

        Order order = new Order();
        order.setRestaurant(session.getBranch());
        order.setDiningTable(session.getTable());
        order.setTableSession(session);
        order.setType("Dine In");
        order.setChannel("QR");
        order.setStatus("DRAFT");
        order.setPaymentStatus("Unpaid");
        order.setNotes(request.notes());
        order.setDiscountAmount(BigDecimal.ZERO);

        BigDecimal total = BigDecimal.ZERO;
        List<OrderItem> items = new ArrayList<>();
        for (GuestOrderRequest.Item requested : request.items()) {
            Product product = products.findByIdAndRestaurant_Id(requested.productId(), session.getBranch().getId())
                    .filter(Product::isAvailable)
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                            "One or more menu items are unavailable"));
            OrderItem item = new OrderItem();
            item.setOrder(order);
            item.setProduct(product);
            item.setQuantity(requested.quantity());
            item.setPrice(product.getPrice());
            item.setNotes(requested.notes());
            item.setStatus("Pending");
            items.add(item);
            total = total.add(product.getPrice().multiply(BigDecimal.valueOf(requested.quantity())));
        }
        order.setTotalAmount(total);
        Order saved = orders.saveAndFlush(order);
        items.forEach(item -> item.setOrder(saved));
        orderItems.saveAll(items);
        QrOrderIdempotency idempotency = new QrOrderIdempotency();
        idempotency.setSession(session);
        idempotency.setIdempotencyKey(key);
        idempotency.setOrder(saved);
        idempotencies.save(idempotency);
        return guestOrder(saved);
    }

    @Transactional(readOnly = true)
    public GuestOrderResponse status(String token, Long orderId) {
        TableSession session = tokenService.resolve(token);
        Order order = orders.findByIdAndTableSession_Id(orderId, session.getId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Order not found"));
        return guestOrder(order);
    }

    @Transactional
    public boolean callWaiter(String token) {
        TableSession session = tokenService.lockAndResolve(token);
        OffsetDateTime oneMinuteAgo = OffsetDateTime.now().minusMinutes(1);
        if (serviceRequests.findFirstBySession_IdAndStatusAndCreatedAtAfterOrderByCreatedAtDesc(
                session.getId(), "OPEN", oneMinuteAgo).isPresent()) return false;
        GuestServiceRequest call = new GuestServiceRequest();
        call.setSession(session);
        serviceRequests.save(call);
        return true;
    }

    @Transactional(readOnly = true)
    public List<java.util.Map<String, Object>> pendingCalls(Long branchId) {
        return serviceRequests.findBySession_Branch_IdAndStatusOrderByCreatedAtAsc(branchId, "OPEN").stream()
                .map(r -> java.util.Map.<String, Object>of("id", r.getId(), "tableLabel",
                        r.getSession().getTable().getTableNumber(), "createdAt", r.getCreatedAt()))
                .toList();
    }

    @Transactional
    public void acknowledgeCall(Long requestId, Long branchId) {
        GuestServiceRequest request = serviceRequests.findById(requestId)
                .filter(r -> Objects.equals(r.getSession().getBranch().getId(), branchId))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Service request not found"));
        request.setStatus("ACKNOWLEDGED");
        request.setAcknowledgedAt(OffsetDateTime.now());
    }

    @Transactional(readOnly = true)
    public Long getCallBranchId(Long requestId) {
        return serviceRequests.findById(requestId)
                .map(r -> r.getSession().getBranch().getId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Service request not found"));
    }

    private GuestOrderResponse guestOrder(Order order) {
        List<GuestOrderResponse.Item> items = orderItems.findByOrder_Id(order.getId()).stream()
                .map(i -> new GuestOrderResponse.Item(i.getProduct().getName(), i.getQuantity())).toList();
        return new GuestOrderResponse(order.getId(), order.getStatus(), order.getOrderTime(), items);
    }
}
