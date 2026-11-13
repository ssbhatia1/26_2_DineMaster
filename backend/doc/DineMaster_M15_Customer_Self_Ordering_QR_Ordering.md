# DineMaster — M15: Customer Self-Ordering / QR Ordering

**Module type:** EDGE  
**Primary users:** Guests  
**Source basis:** DineMaster Technical Documentation, Module M15  
**Implementation note:** This module exists in v1.0.0 using Shelf on port `8080` with vanilla HTML/CSS/JavaScript. The customer-facing experience is a browser website, **not a Flutter screen**.

## 1. Module objective

Allow restaurant guests to place orders from their own phones by scanning a table QR code. Guests do not need to install an application.

Guest journey:
1. Scan the QR code placed on the table.
2. Open the restaurant menu in the phone browser.
3. Browse menu items and add items to the cart.
4. Submit the order.
5. See order confirmation/status.
6. Optionally call a waiter.

The module runs on the restaurant Edge server and integrates with the existing Order and Waiter flows.

## 2. Scope and submodules

### 2.1 Table QR access
- Each table has a QR code.
- QR contains a signed/random table-session token.
- Token is bound to a table and one seating session.
- A token is not a guessable table ID.

### 2.2 Guest menu browsing
- Guest opens the menu using the QR link.
- Menu is served for the table represented by the valid token.
- Menu should reflect items available to that branch/table context.

### 2.3 Guest cart
- Guest selects items and quantities.
- Quantity validation: `1–10` per item.
- Item limit per order: default `20`.
- Guest can review the cart before submitting.

### 2.4 Order submission
- Guest submits the cart to the Edge server.
- Order is created in the Order module with `status = DRAFT` and `channel = QR`.
- Staff must accept the order before normal KOT processing.
- Configurable auto-accept is mentioned as an assumption, not a confirmed default.
- No payment is included in the MVP.

### 2.5 Order confirmation and status
- Guest can view the status of their submitted order.
- Status is retrieved using the valid table token.
- Order lifecycle/KOT handling remains in the Order and Kitchen modules.

### 2.6 Call waiter
- Guest can request waiter assistance from the QR web page.
- Edge notifies the Waiter workflow.

## 3. Screens / web pages

The source specifies three browser pages:

| Page | Responsibility |
|---|---|
| Menu | Display the menu for the QR table session |
| Cart | Review selected items and submit the order |
| Status | Show submitted order status/confirmation |

Additional UI behaviour:
- Plain HTML, CSS and JavaScript.
- Use `fetch` for HTTP API calls.
- Use WebSocket for live updates.
- Loading, error and offline states.
- Offline message: **“Connect to restaurant Wi-Fi”**.
- This is a guest-facing web page, not Flutter.

## 4. Guest workflow

### 4.1 Scan QR and open menu
1. Guest scans the QR code printed for the table.
2. Browser opens the Edge-hosted menu URL with the token.
3. Edge validates the token.
4. Edge resolves the associated table session.
5. Guest receives the menu for that session.

If the token is invalid or expired, do not expose table or staff details. Show a safe message and ask the guest to contact restaurant staff.

### 4.2 Add items and submit
1. Guest browses menu.
2. Guest adds items to the cart.
3. Validate each item quantity from `1` to `10`.
4. Enforce the default maximum of `20` items per order.
5. Guest reviews cart and submits.
6. Browser sends `POST /guest/orders` with an `Idempotency-Key`.
7. Edge validates token, item availability and request limits.
8. Edge creates a `DRAFT` order with `channel = QR`.
9. Staff accepts the order.
10. Accepted order continues through the normal KOT flow.

### 4.3 Track order
1. Guest opens the Status page.
2. Browser calls the guest order-status endpoint using the table token.
3. Edge returns only guest-safe order status information.
4. WebSocket may update the page when the order status changes.

### 4.4 Call waiter
1. Guest taps Call Waiter.
2. Browser sends the call-waiter request using the signed token.
3. Edge validates the session and rate limits the request.
4. Edge notifies the Waiter workflow.

## 5. API specification

The source defines these guest endpoints.

| Method | Endpoint | Authentication | Purpose |
|---|---|---|---|
| `GET` | `/guest/menu?t=<token>` | Signed token | Get menu for the table |
| `POST` | `/guest/orders` | Signed token + `Idempotency-Key` | Submit guest order |
| `GET` | `/guest/orders/{id}?t=` | Signed token | Get order status |
| `POST` | `/guest/call-waiter?t=` | Signed token | Alert waiter |

### 5.1 Get guest menu
`GET /guest/menu?t=<token>`
- Validate signed/random table-session token.
- Resolve table and active session.
- Return menu information only; do not expose staff data.
- Reject expired/closed sessions.

### 5.2 Submit guest order
`POST /guest/orders`

Headers:
```http
Idempotency-Key: <unique-request-key>
Content-Type: application/json
```

Authentication: signed table-session token.

The source does not prescribe a complete request/response JSON schema. Align the payload with the existing Order module contract; do not create a separate guest-only order model unless required.

Required behaviour:
- Create order with `DRAFT` status.
- Set order channel to `QR`.
- Validate item quantity `1–10`.
- Enforce default item limit `20`.
- Require staff acceptance before KOT, unless configurable auto-accept is explicitly approved.
- Use idempotency to prevent duplicate orders on retries.

### 5.3 Get order status
`GET /guest/orders/{id}?t=<token>`
- Validate token.
- Verify the requested order belongs to the same table session/table.
- Return guest-safe status only.
- Do not expose internal staff data or unrelated orders.

### 5.4 Call waiter
`POST /guest/call-waiter?t=<token>`
- Validate token/session.
- Apply rate limiting.
- Notify the Waiter workflow.
- Return a safe acknowledgement.

## 6. Database design

The source specifies:

`table_sessions(id, branch_id, table_id, token_hash, opened_at, expires_at, closed_at)`

| Field | Purpose |
|---|---|
| `id` | Table session identifier |
| `branch_id` | Restaurant branch |
| `table_id` | Table associated with this session |
| `token_hash` | Hashed token value; do not store raw token |
| `opened_at` | Session opening time |
| `expires_at` | Session expiry time |
| `closed_at` | Session closure time |

The source does not provide a complete DDL or additional indexes. Follow the canonical database schema and existing Edge migration conventions.

### 6.1 Session/token lifecycle
- One table token is valid for one seating session.
- Token is bound to the table and session.
- Token expires when the table is released or after `4 hours`, as stated in the source.
- On table release, close the session and invalidate the token.
- Store token hash, not the raw token.

## 7. QR token design and security

The source defines the QR content format:

```text
http(s)://<edge>/menu?t=<token>
```

Do **not** encode a guessable table identifier such as `?table=<ID>`.

Token requirements:
- Generate a cryptographically random `128-bit` token.
- Store only its hash in `table_sessions.token_hash`.
- Bind token to one table and one seating session.
- Expire at table release or after `4 hours`.
- Reject tampered, unknown, expired or closed-session tokens.

### 7.1 Network and browser security
- Rate limit: `30 requests per minute per IP`.
- Do not expose staff data to guest endpoints.
- Escape all guest-submitted text before rendering.
- Restrict CORS to the Edge origin.
- Plain HTTP risk is accepted only when the network is private.
- Otherwise use local TLS.
- Wi-Fi isolation must be checked: guests must be able to reach the Edge server but must not be able to reach staff devices.

### 7.2 Abuse prevention
- Validate every submitted product against the current menu/availability.
- Enforce item quantity and order item limits server-side.
- Use idempotency for order submission.
- Rate limit guest endpoints.
- Do not trust client-side cart totals or product availability.

## 8. Architecture and integration

### Edge backend
- `GuestController`
- `TableTokenService`
- Guest menu/order/status/call-waiter endpoints
- Integration with Order module
- Notification to Waiter workflow

### Guest frontend
- Plain HTML/CSS/JavaScript
- `fetch` for REST endpoints
- WebSocket for live status
- Menu, Cart and Status pages
- Loading, error and offline states

### Dependencies
- Table/Floor Management — table and seating session.
- Menu/Product Management — guest menu and item availability.
- Order Management — create QR draft order.
- Kitchen/KOT — normal downstream order processing after staff acceptance.
- Waiter Management/Notification — call waiter and order handling.

## 9. Business rules

| Rule | Required behaviour |
|---|---|
| Guest application | Browser-based; no app installation |
| Order status at creation | `DRAFT` |
| Order channel | `QR` |
| Staff acceptance | Required before KOT |
| Auto-accept | Configurable assumption; confirm before enabling |
| Token scope | One table, one seating session |
| Token generation | Random 128-bit |
| Token storage | Store hash |
| Token expiry | Table release or 4 hours |
| Item quantity | `1–10` |
| Item limit | Default 20 per order |
| Payment | Not included in MVP |
| Rate limit | 30 requests/minute/IP |
| Network | Guest can reach Edge; guest Wi-Fi isolated from staff devices |

## 10. Error and edge cases

The source explicitly calls for testing:
- Tampered token.
- Expired token.
- Spam orders.
- Two guests ordering from the same table.
- Unavailable item.
- Wi-Fi isolation.

Recommended expected handling:
- Invalid/expired token: reject request and show a safe session-expired message.
- Duplicate submission: idempotency key returns the original result rather than creating another order.
- Unavailable item: reject or request cart refresh; do not silently add unavailable items.
- Rate limit exceeded: return `429 Too Many Requests`.
- Edge unreachable: show **“Connect to restaurant Wi-Fi”** / connection guidance.

Response details above are implementation recommendations where the source does not define exact HTTP status codes.

## 11. Testing checklist

### Token/session tests
- Valid token resolves correct table session.
- Tampered token is rejected.
- Expired token is rejected.
- Closed session token is rejected.
- Token cannot be used for another table.
- Raw token is never stored in the database.

### Guest order tests
- Guest can retrieve menu with a valid token.
- Quantity below 1 or above 10 is rejected.
- More than 20 items is rejected by default.
- Unavailable item is rejected.
- New order has `DRAFT` status and `QR` channel.
- Staff acceptance is required before KOT.
- Duplicate request with same idempotency key does not create duplicate order.
- Two guests on the same table can submit orders without corrupting each other's carts/orders.

### Security/network tests
- Rate limit is enforced at 30 requests/minute/IP.
- Guest endpoints do not return staff data.
- Guest text is safely escaped.
- CORS is restricted to Edge origin.
- Wi-Fi isolation allows guest-to-Edge traffic but blocks guest-to-staff-device traffic.
- Local TLS is used when the network is not private.

### Realtime/UI tests
- Menu, Cart and Status pages load in supported mobile browsers.
- WebSocket status update is reflected on Status page.
- Edge unreachable state displays the specified Wi-Fi message.
- Browser refresh/retry does not duplicate submitted orders.

### Acceptance criteria
- Guest can scan a table QR and open the menu without installing an app.
- Guest can submit a QR order.
- Order is created as `DRAFT` with channel `QR`.
- Staff can accept it and continue the normal KOT flow.
- Guest can view order status and call a waiter.
- Token security, expiry, rate limiting and Wi-Fi isolation pass tests.
- No payment is taken in this MVP module.

## 12. Recommended implementation sequence

1. Verify the existing v1.0.0 Shelf/Edge server on port `8080`.
2. Inspect the existing vanilla HTML/CSS/JS guest pages before replacing or duplicating them.
3. Implement/verify `table_sessions` migration.
4. Implement random 128-bit token generation and hash storage.
5. Implement token validation and session expiry.
6. Implement `GET /guest/menu`.
7. Implement guest cart validation and `POST /guest/orders` with idempotency.
8. Integrate QR draft orders with staff acceptance and normal KOT flow.
9. Implement `GET /guest/orders/{id}` status endpoint.
10. Implement `POST /guest/call-waiter`.
11. Implement WebSocket status updates.
12. Add rate limits, escaping, CORS and network isolation checks.
13. Build/verify QR print template.
14. Test on real phones connected to the restaurant guest Wi-Fi.

## 13. Open decisions / assumptions to confirm

- Is staff acceptance always required, or is configurable auto-accept approved?
- Is the default maximum of 20 order items acceptable for every branch?
- Is the 4-hour token expiry appropriate for the restaurant's longest seating?
- Does table release always close the session immediately?
- Which exact order statuses are visible to guests?
- What is the guest-facing behaviour when an item becomes unavailable after it was added to the cart?
- Is local TLS provisioned for the Edge host, or is guest Wi-Fi guaranteed to be a private trusted network?

---

**Source boundary:** This document follows the M15 source requirements: Edge module, guest browser/no app, Shelf port 8080 and vanilla HTML/CSS/JS, QR/menu/cart/submit/confirmation/call waiter, QR draft order and staff acceptance assumption, one token per seating session, default item limit 20, quantity 1–10, no payment in MVP, Menu/Cart/Status pages, `GuestController`, `TableTokenService`, `table_sessions`, four guest endpoints, 128-bit token/hash/expiry rules, rate limit, guest privacy, escaping, CORS, TLS/network guidance, listed test cases and QR print template. Where the source does not define exact request/response schemas, status codes or full DDL, this document does not present them as confirmed requirements.
