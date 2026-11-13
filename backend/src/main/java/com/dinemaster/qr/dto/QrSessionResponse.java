package com.dinemaster.qr.dto;

import java.time.OffsetDateTime;

public record QrSessionResponse(Long sessionId, Long tableId, String tableLabel,
                                String token, String menuUrl, OffsetDateTime expiresAt) {}
