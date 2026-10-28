# DineMaster Project Handoff

## Purpose

DineMaster is a restaurant POS and management system.

Workspace:

```text
C:\Users\trupt\26_2_DineMaster
```

The application has two intended data modes:

```text
Offline: Flutter -> SQLite
Online:  Flutter -> HTTP REST -> Spring Boot -> PostgreSQL
```

Cloudinary is intentionally postponed and must not block local development.

## Non-Negotiable Rules

- Preserve the existing offline SQLite schema, data, repositories, and workflows.
- Do not reset, truncate, drop, or recreate the user's existing databases.
- Do not use arbitrary SQL over HTTP as a replacement for domain REST APIs.
- Do not expose passwords, JWT secrets, or database credentials in code, logs, commits, or chat.
- Preserve existing user changes and untracked files.
- Keep online and offline data paths separate.
- Do not add Cloudinary until explicitly requested.
- Do not claim PostgreSQL production compatibility until the real local PostgreSQL database has been migrated and tested.

## Repository Layout

```text
backend/                 Spring Boot backend
backend/src/main/java/   Java entities, repositories, DTOs, services, controllers
backend/src/main/resources/application.yml
backend/src/main/resources/db/migration/ Flyway migrations
backend/src/test/java/   Spring/H2 tests
frontend/                Flutter application
frontend/lib/models/     Product, order, table, user models
frontend/lib/repositories/ SQLite and REST data access
frontend/lib/services/   Backend API client, local sync server, sync service
frontend/lib/core/database/ SQLite database helper and old network database
frontend/lib/screens/    Flutter UI screens
```

There are also existing audit reports, backups, logs, generated Flutter files, and untracked backend files. Do not delete them without explicit approval.

## Port Design

```text
Spring Boot REST API:     8081
Offline HTTP sync server: 8082
Offline WebSocket sync:   8083
PostgreSQL:               5432
```

The WebSocket was moved away from 8081 because Spring Boot also uses 8081. Offline SQLite itself does not use a database TCP port; 8082/8083 are synchronization services.

## Backend Configuration

Main file:

```text
backend/src/main/resources/application.yml
```

Defaults/configuration:

```text
SERVER_PORT=8081
DB_HOST=localhost
DB_PORT=5432
DB_NAME=dinemaster
DB_USERNAME=postgres
DB_PASSWORD=<local value>
SPRING_PROFILES_ACTIVE=local
JWT_SECRET=<minimum 32-byte local value>
JWT_EXPIRATION_MS=86400000
JPA_DDL_AUTO=validate
```

The local PostgreSQL password and JWT secret must be set in the same PowerShell session that starts Maven. Never send their values to an AI or put them in the repository.

Example:

```powershell
cd C:\Users\trupt\26_2_DineMaster\backend
$env:DB_PASSWORD = Read-Host "Enter PostgreSQL password"
$env:JWT_SECRET = ([guid]::NewGuid().ToString() + [guid]::NewGuid().ToString())
.\mvnw.cmd spring-boot:run
```

Successful startup contains:

```text
Started DineMasterApplication
```

Health check:

```powershell
Invoke-RestMethod http://localhost:8081/api/health
```

Product check:

```powershell
Invoke-RestMethod http://localhost:8081/api/products
```

A previous startup failure was caused by an empty DB_PASSWORD and PostgreSQL SCRAM authentication, not by Java compilation or port configuration.

## Backend Migrations

Flyway migrations currently present:

```text
V1__create_core_tables.sql
V2__create_orders_tables.sql
V3__preserve_product_food_types.sql
V4__create_inventory_and_bookings.sql
V5__create_kot_tables.sql
V6__create_recipes_table.sql
```

Important schema decisions:

- Money uses NUMERIC/BigDecimal.
- IDs use BIGINT/Long.
- Product food type is integer `0..3`, not boolean:
  - 0 = Non-Veg
  - 1 = Veg
  - 2 = Egg
  - 3 = Jain
- V3 converts old PostgreSQL boolean product values safely:
  - TRUE -> 1
  - FALSE -> 0
- V4 adds inventory and bookings.
- V5 adds KOT and `order_items.kot_id`.
- V6 adds recipes using `product_id`, `ingredient_id`, and `quantity_used`.

The real local PostgreSQL migration has not been fully proven in this handoff. Existing automated tests use H2 with Hibernate create-drop and do not replace a PostgreSQL migration rehearsal.

## Backend Controllers and APIs

### Health

```text
GET /api/health
```

### Authentication

```text
POST /api/auth/login
```

JWT login returns a token and password-free user response.

### Users

```text
GET    /api/users
GET    /api/users/{id}
POST   /api/users
PUT    /api/users/{id}
DELETE /api/users/{id}
```

User management is admin-only. Owner/Manager authorities are required. Login is public; user CRUD is protected. Passwords are stored using BCrypt and are never returned in UserResponse.

Roles currently intended:

```text
OWNER, MANAGER, WAITER, CHEF, CASHIER
```

The frontend login/user-management screens are not yet fully connected to JWT REST mode.

### Restaurants

```text
GET    /api/restaurants
GET    /api/restaurants/{id}
POST   /api/restaurants
PUT    /api/restaurants/{id}
DELETE /api/restaurants/{id}
```

### Categories

```text
GET    /api/categories
GET    /api/categories/{id}
POST   /api/categories
PUT    /api/categories/{id}
DELETE /api/categories/{id}
```

### Products

```text
GET    /api/products
GET    /api/products/all
GET    /api/products/{id}
GET    /api/products/category/{category}
POST   /api/products
PUT    /api/products/{id}
DELETE /api/products/{id}
```

Optional product list/category query parameter:

```text
?restaurantId=<id>
```

Product responses preserve `is_veg` and `is_available` compatibility. Product restaurant mapping exists, but all product create/update flows should continue to be reviewed for mandatory restaurant assignment.

### Customers

```text
GET    /api/customers
GET    /api/customers/{id}
POST   /api/customers
PUT    /api/customers/{id}
DELETE /api/customers/{id}
```

### Tables

```text
GET    /api/tables?restaurantId=<id>
GET    /api/tables/{id}
POST   /api/tables
PUT    /api/tables/{id}
PATCH  /api/tables/{id}/status?status=<value>
DELETE /api/tables/{id}
```

### Orders

```text
POST   /api/orders
GET    /api/orders?restaurantId=<id>
GET    /api/orders/{id}
GET    /api/orders/{id}/items
PATCH  /api/orders/{id}/status
POST   /api/orders/{id}/hold
POST   /api/orders/{id}/cancel
POST   /api/orders/{id}/payment
```

Order lifecycle status validation exists. Paid orders cannot be cancelled. Cancelled orders cannot be paid.

### Inventory

```text
GET    /api/inventory?restaurantId=<id>
POST   /api/inventory
PUT    /api/inventory/{id}
PATCH  /api/inventory/{id}/stock
DELETE /api/inventory/{id}
```

Stock adjustment modes:

```text
add, deduct, set
```

Negative stock is rejected.

### Bookings

```text
GET    /api/bookings?restaurantId=<id>
POST   /api/bookings
PUT    /api/bookings/{id}
PATCH  /api/bookings/{id}/status?value=<status>
DELETE /api/bookings/{id}
```

Booking status values:

```text
Pending, Confirmed, Cancelled, Completed
```

Table, restaurant, and optional customer references are validated.

### KOT

```text
GET    /api/kot/order/{orderId}
POST   /api/kot
PATCH  /api/kot/{id}/status?value=<status>
POST   /api/kot/{kotId}/items/{itemId}
DELETE /api/kot/{kotId}/items/{itemId}
```

KOT statuses:

```text
Pending, Cooking, Ready, Served, Cancelled
```

Cooking/Ready/Served timestamps are recorded. An order item can only be assigned to a KOT belonging to the same order.

### Recipes

```text
GET    /api/recipes?productId=<id>
POST   /api/recipes
PUT    /api/recipes/{id}
DELETE /api/recipes/{id}
```

Product and ingredient must belong to the same restaurant. Quantity must be positive.

## Frontend REST Layer

HTTP client:

```text
frontend/lib/services/backend_api_client.dart
```

Features:

- GET, POST, PUT, PATCH, DELETE
- Five-second connection timeout
- JSON parsing
- HTTP error conversion
- Invalid JSON handling
- Configurable `backend_api_url`
- Client device fallback to `server_ip`

API mode preference:

```text
use_backend_api = true/false
```

Default is false, preserving SQLite behavior.

Repositories:

```text
frontend/lib/repositories/product_repository.dart
frontend/lib/repositories/table_repository.dart
frontend/lib/repositories/order_api_repository.dart
```

Products and tables route to REST when API mode is enabled. Order API repository supports create, list, detail, items, status, hold, cancel, and payment.

Order history screen currently has an online branch for:

- Order list
- Search/filter handling after REST load
- Invoice items
- Payment

The order model accepts both SQLite string values and REST numeric JSON values. It also accepts snake_case and camelCase fields.

## Frontend Still Using SQLite Directly

These screens still contain direct `DatabaseHelper.instance.database` calls and are not fully REST-routed:

- POS
- Full order history actions
- Inventory
- Bookings
- KOT
- Recipe management
- Login
- User management
- Analytics
- Overview/dashboard aggregates
- Accounts/expenses
- Branch/restaurants
- Product management complex recipe/inventory operations
- Waiter order flows

Do not replace these with generic SQL-over-HTTP. Add domain repositories/facades and preserve the SQLite branch.

## Offline Behavior

Offline path remains:

```text
Flutter -> DatabaseHelper -> SQLite
```

The existing offline sync service uses:

```text
HTTP 8082
WebSocket 8083
```

Do not remove or reset offline tables. The REST mode is opt-in and should not affect offline behavior when `use_backend_api` is false.

## Tests and Verification

Latest confirmed backend test result:

```text
Tests run: 8
Failures: 0
Errors: 0
BUILD SUCCESS
```

Latest focused Flutter tests after order-history changes:

```text
18 passed
```

Flutter analyzer for the order REST slice was clean.

Test files currently include:

```text
backend/src/test/java/com/dinemaster/DineMasterApplicationTests.java
backend/src/test/java/com/dinemaster/HealthControllerTest.java
backend/src/test/java/com/dinemaster/OrderControllerTest.java
backend/src/test/java/com/dinemaster/ProductControllerTest.java
```

Backend tests currently cover health, application context, order reads/lifecycle, and product JSON/type validation. Inventory, bookings, KOT, recipes, and JWT need dedicated endpoint tests before being considered production verified.

The recent Maven test log showed Java 23 running even though `pom.xml` targets Java 21. Verify with:

```powershell
java -version
.\mvnw.cmd -version
```

Do not claim Java 21 runtime verification unless both commands confirm it.

## Current Production Gaps

- Full frontend REST routing is incomplete.
- Real PostgreSQL Flyway migration/write-read verification is incomplete.
- JWT frontend login/token storage/role UI is incomplete.
- JWT refresh/revocation/password reset are missing.
- Analytics and expenses APIs are missing.
- Inventory history and recipe-driven stock deduction are missing.
- Booking overlap validation is incomplete.
- KOT item quantity/status workflow needs expansion.
- Global exception/error response format is missing.
- Audit logging, pagination, rate limiting, CORS allowlist, HTTPS, backups, monitoring, deployment, and CVE scan remain.
- Cloudinary is postponed.

## Recommended Next Work

1. Verify Java runtime version and local PostgreSQL migration.
2. Add frontend JWT login and admin-only user management.
3. Route POS order creation/payment/status through REST.
4. Route inventory, booking, KOT, and recipe screens through REST repositories.
5. Add inventory/KOT/booking/recipe/JWT endpoint tests.
6. Add analytics and expenses APIs.
7. Run full Flutter tests and a live Flutter -> REST -> PostgreSQL flow.

## Handoff Instruction

Continue this project from the existing workspace. Do not reset or discard changes. Preserve offline SQLite. The backend has a working REST foundation and latest backend tests passed 8/8, but all frontend screens are not online-integrated. Start by verifying current files and Java/PostgreSQL environment, then implement one vertical REST flow at a time with tests after each change.
