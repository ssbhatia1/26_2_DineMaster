package com.dinemaster.qr.service;

import com.dinemaster.diningtable.entity.DiningTable;
import com.dinemaster.diningtable.repository.DiningTableRepository;
import com.dinemaster.qr.dto.QrSessionResponse;
import com.dinemaster.qr.entity.TableSession;
import com.dinemaster.qr.repository.TableSessionRepository;
import com.dinemaster.restaurant.entity.Restaurant;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.util.Base64;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class TableSessionService {
    private static final SecureRandom RANDOM = new SecureRandom();
    private final TableSessionRepository sessions;
    private final DiningTableRepository tables;
    private final String menuBaseUrl;

    public TableSessionService(TableSessionRepository sessions, DiningTableRepository tables,
            @Value("${dinemaster.guest.menu-base-url:/menu}") String menuBaseUrl) {
        this.sessions = sessions;
        this.tables = tables;
        this.menuBaseUrl = menuBaseUrl;
    }

    @Transactional
    public QrSessionResponse open(Long tableId) {
        DiningTable table = tables.findForUpdateById(tableId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Table not found"));
        Restaurant branch = table.getRestaurant();
        if (!table.isActive() || branch == null || !branch.isActive()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Table is inactive");
        }
        String status = table.getStatus() == null ? "" : table.getStatus().trim();
        if (status.equalsIgnoreCase("Available") || status.equalsIgnoreCase("Cleaning")
                || status.equalsIgnoreCase("Out Of Service")) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Seat the guests before opening a QR session");
        }
        OffsetDateTime now = OffsetDateTime.now();
        sessions.lockOpenForTable(tableId).forEach(s -> s.setClosedAt(now));
        byte[] bytes = new byte[16];
        RANDOM.nextBytes(bytes);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        TableSession session = new TableSession();
        session.setBranch(branch);
        session.setTable(table);
        session.setTokenHash(hash(token));
        session.setExpiresAt(now.plusHours(4));
        TableSession saved = sessions.saveAndFlush(session);
        String base = menuBaseUrl.endsWith("?") || menuBaseUrl.endsWith("&")
                ? menuBaseUrl : menuBaseUrl + (menuBaseUrl.contains("?") ? "&" : "?");
        return new QrSessionResponse(saved.getId(), tableId, table.getTableNumber(), token,
                base + "t=" + token, saved.getExpiresAt());
    }

    @Transactional
    public void closeForTable(Long tableId) {
        OffsetDateTime now = OffsetDateTime.now();
        sessions.lockOpenForTable(tableId).forEach(s -> s.setClosedAt(now));
    }

    @Transactional(readOnly = true)
    public TableSession resolve(String token) {
        if (token == null || token.length() < 20 || token.length() > 100) throw expired();
        TableSession session = sessions.findByTokenHash(hash(token)).orElseThrow(TableSessionService::expired);
        if (!session.isValidAt(OffsetDateTime.now()) || !session.getTable().isActive()
                || session.getTable().getRestaurant() == null || !session.getTable().getRestaurant().isActive()) {
            throw expired();
        }
        return session;
    }

    @Transactional
    public TableSession lockAndResolve(String token) {
        TableSession found = resolve(token);
        TableSession locked = sessions.lockById(found.getId()).orElseThrow(TableSessionService::expired);
        if (!locked.isValidAt(OffsetDateTime.now())) throw expired();
        return locked;
    }

    private static ResponseStatusException expired() {
        return new ResponseStatusException(HttpStatus.GONE, "QR table session is invalid or expired");
    }

    private static String hash(String token) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8));
            return java.util.HexFormat.of().formatHex(digest);
        } catch (Exception e) { throw new IllegalStateException("SHA-256 is unavailable", e); }
    }
}
