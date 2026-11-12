package com.dinemaster.auth.service;



import com.dinemaster.user.entity.User;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.JwtParser;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.Date;
import java.util.List;
import java.util.UUID;

@Service
public class JwtService {
    private final String secret;
    private final long expirationMs;
    private final PrivateKey privateKey;
    private final PublicKey publicKey;

    public JwtService(@Value("${app.jwt.secret:}") String secret,
            @Value("${app.jwt.expiration-ms:900000}") long expirationMs,
            @Value("${app.jwt.private-key-pem:}") String privateKeyPem,
            @Value("${app.jwt.public-key-pem:}") String publicKeyPem) {
        this.secret = secret == null ? "" : secret;
        this.expirationMs = expirationMs;
        boolean hasPrivate = privateKeyPem != null && !privateKeyPem.isBlank();
        boolean hasPublic = publicKeyPem != null && !publicKeyPem.isBlank();
        if (hasPrivate != hasPublic) {
            throw new IllegalStateException("JWT_PRIVATE_KEY_PEM and JWT_PUBLIC_KEY_PEM must be configured together");
        }
        if (hasPrivate) {
            this.privateKey = parsePrivateKey(privateKeyPem);
            this.publicKey = parsePublicKey(publicKeyPem);
        } else {
            this.privateKey = null;
            this.publicKey = null;
            if (this.secret.getBytes(StandardCharsets.UTF_8).length < 32) {
                throw new IllegalStateException(
                        "Configure an RSA JWT key pair or a JWT_SECRET of at least 32 bytes before starting the backend.");
            }
        }
    }

    public String createToken(User user, UUID deviceId, List<Long> branchIds) {
        var builder = Jwts.builder()
                .subject(user.getUsername())
                .claim("userId", user.getId())
                .claim("role", com.dinemaster.role.Roles.canonical(user.getRole()))
                .claim("roles", List.of(com.dinemaster.role.Roles.canonical(user.getRole())))
                .claim("tenantId", user.getTenantId())
                .claim("branchIds", branchIds)
                .claim("deviceId", deviceId == null ? null : deviceId.toString())
                .claim("permVersion", user.getPermissionVersion())
                .issuedAt(new Date())
                .expiration(new Date(System.currentTimeMillis() + expirationMs));
        if (privateKey == null) builder.signWith(key(), Jwts.SIG.HS256);
        else builder.signWith(privateKey, Jwts.SIG.RS256);
        return builder.compact();
    }

    public String username(String token) {
        return claims(token).getSubject();
    }

    public Claims claims(String token) {
        JwtParser parser = publicKey == null
                ? Jwts.parser().verifyWith(key()).build()
                : Jwts.parser().verifyWith(publicKey).build();
        return parser.parseSignedClaims(token).getPayload();
    }

    public long getAccessLifetimeSeconds() { return expirationMs / 1000; }

    public Map<String, Object> jwks() {
        if (!(publicKey instanceof RSAPublicKey rsaKey)) {
            throw new IllegalStateException("JWKS is available only when RSA JWT keys are configured");
        }
        return Map.of("keys", java.util.List.of(Map.of(
                "kty", "RSA",
                "use", "sig",
                "alg", "RS256",
                "kid", keyId,
                "n", Base64.getUrlEncoder().withoutPadding().encodeToString(unsigned(rsaKey.getModulus().toByteArray())),
                "e", Base64.getUrlEncoder().withoutPadding().encodeToString(unsigned(rsaKey.getPublicExponent().toByteArray())))));
    }

    private byte[] unsigned(byte[] value) {
        return value.length > 1 && value[0] == 0 ? java.util.Arrays.copyOfRange(value, 1, value.length) : value;
    }

    private SecretKey key() {
        if (secret == null || secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException("JWT_SECRET must be at least 32 bytes");
        }
        return Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    }

    private PrivateKey parsePrivateKey(String pem) {
        try {
            byte[] encoded = Base64.getDecoder().decode(stripPem(pem));
            return KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(encoded));
        } catch (Exception exception) {
            throw new IllegalStateException("JWT_PRIVATE_KEY_PEM must contain a valid PKCS#8 RSA private key", exception);
        }
    }

    private PublicKey parsePublicKey(String pem) {
        try {
            byte[] encoded = Base64.getDecoder().decode(stripPem(pem));
            return KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(encoded));
        } catch (Exception exception) {
            throw new IllegalStateException("JWT_PUBLIC_KEY_PEM must contain a valid X.509 RSA public key", exception);
        }
    }

    private String stripPem(String pem) {
        return pem.replaceAll("-----BEGIN [^-]+-----", "")
                .replaceAll("-----END [^-]+-----", "")
                .replaceAll("\\s", "");
    }
}
