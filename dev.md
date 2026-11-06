# DineMaster — Developer Documentation

> **Internal Reference Document** · Version 1.0.0 · Last Updated: September 2026

---

## 📌 Project Title

**DineMaster** *(codename: KOS — Kitchen Operating System)*

---

## 🧭 Project Overview

DineMaster is an **enterprise-grade, cross-platform Restaurant ERP & POS Management System** built entirely with Flutter and SQLite. It is designed to digitize and unify every operational touchpoint of a modern restaurant — from the moment a customer walks in, to the final payment and kitchen cleanup — all running **100% offline** on the local network with no cloud dependency.

The system consolidates four core domains under a single application:

| Domain | Coverage |
|--------|----------|
| **Front of House** | POS billing, table management, reservations, customer self-ordering |
| **Back of House** | Kitchen Display System (KDS), KOT management, recipe & inventory control |
| **Management** | Analytics dashboard, financial accounting, staff & RBAC management |
| **Infrastructure** | Multi-branch support, hardware integrations, CI/CD pipelines |

---

## 📝 Project Summary

DineMaster was built to solve the fragmentation problem found in most restaurant setups — where billing software, kitchen displays, waiter apps, and inventory management are all separate tools that rarely talk to each other.

The system runs a **built-in local HTTP & WebSocket server** (Shelf) that enables all devices on the restaurant's local Wi-Fi — tablets, smartphones, kitchen screens, POS terminals — to stay in perfect real-time sync without requiring the internet.

**Key highlights:**
- 🏪 Multi-branch restaurant support with data isolation per outlet
- 🧑‍🍳 Paperless Kitchen Display System with live KOT tracking
- 📱 QR-code based customer self-ordering — no app download required
- 🧾 Thermal ESC/POS receipt printing + PDF invoice generation
- 📊 Built-in analytics, P&L accounting, and expense management
- 🔐 Role-Based Access Control (Admin, Manager, Cashier, Waiter, Chef)
- 🌐 Cross-platform: Windows, macOS, Linux, Android, iOS, Web

**Default Login Credentials:**
```
Username: owner
Password: owner123
```

---

## 🛠️ Project Tech Stack

### Core Framework

| Layer | Technology | Version |
|-------|-----------|---------|
| Frontend Framework | Flutter (Dart) | SDK `^3.11.1` |
| Frontend Database | SQLite | via `sqflite ^2.4.2` & `sqflite_common_ffi` |
| Frontend State Management | BLoC (flutter_bloc) | `^9.1.1` |
| Frontend Routing | GoRouter | `^17.2.3` |
| Frontend Embedded Server | Shelf + Shelf Router | `^1.4.2` / `^1.1.4` |
| Backend Framework | Spring Boot | `3.3.4` (Java 21 LTS) |
| Backend Database | PostgreSQL | 16+ / 18 (with H2 in-memory test fallback) |
| Backend Security | Spring Security 6 & JJWT | Stateless JWT authentication |
| Media Storage | Cloudinary SDK | `^1.39.0` (Environment-configured) |
| Payment Gateway | Decoupled Provider (Razorpay/Stripe) | Secure backend signing architecture |

### Key Dependencies

| Package | Purpose | Version |
|---------|---------|---------|
| `sqflite` | SQLite on mobile | `^2.4.2+1` |
| `sqflite_common_ffi` | SQLite on desktop (Windows/Linux/macOS) | `^2.4.0+3` |
| `flutter_bloc` | BLoC state management | `^9.1.1` |
| `go_router` | Declarative navigation & routing | `^17.2.3` |
| `shelf` | Embedded local HTTP server | `^1.4.2` |
| `shelf_router` | HTTP route handling | `^1.1.4` |
| `pdf` | PDF invoice generation | `^3.12.0` |
| `printing` | In-app PDF preview & printing | `^5.14.3` |
| `qr_flutter` | QR code generation for tables | `^4.1.0` |
| `mobile_scanner` | QR code scanning | `^7.2.0` |
| `flutter_animate` | Micro-animations and UI transitions | `^4.5.2` |
| `video_player` | Recipe training video playback | `^2.11.1` |
| `video_player_win` | Windows-specific video player | `^3.2.2` |
| `intl` | Date, time, and currency formatting | `^0.20.2` |
| `shared_preferences` | Lightweight local key-value storage | `^2.5.5` |
| `connectivity_plus` | Network connectivity detection | `^7.1.1` |
| `file_picker` | Database backup/restore file selection | `^11.0.2` |
| `url_launcher` | Opening external recipe video links | `^6.3.2` |
| `crypto` | Password hashing | `^3.0.6` |
| `logger` | Structured application logging | `^2.8.0` |
| `cupertino_icons` | iOS-style icon set | `^1.0.8` |

### Platform Targets

| Platform | Build Artifact | CI Runner | Status |
|----------|---------------|-----------|--------|
| Windows | `.exe` | `windows-latest` | ✅ Supported |
| macOS | `.app.zip` | `macos-latest` | ✅ Supported |
| Linux | `.tar.gz` | `ubuntu-latest` | ⚠️ Best-effort |
| Android | `.apk` | `ubuntu-latest` | ✅ Supported |
| iOS | `.ipa` / TestFlight | `macos-latest` | ✅ Supported |
| Web | `build/web` | `ubuntu-latest` | ✅ Supported |

### DevOps & Tooling

| Tool | Purpose |
|------|---------|
| GitHub Actions | CI/CD — analysis, testing, multi-platform builds, GitHub Releases |
| `dart analyze` | Static analysis (strict mode) |
| `flutter test` | Unit & widget testing |
| `analysis_options.yaml` | Configured lint rules |
| Python scripts | Build/data utility scripts (`assemble.py`, `fix_types.py`, `update_cart.py`) |

---

## ✨ Project Features

### 1. 🧾 Point of Sale (POS) & High-Speed Billing
- Multi-channel order types: Dine-In, Table, Takeaway, Delivery, Online, Walk-in
- Real-time cart with quantity adjustments, item-level notes, and category navigation
- Multi-slab GST tax computation (0%, 5%, 12%, 18%, configurable)
- Flexible discounts: Flat amount or Percentage with audit remarks
- Payment modes: Cash, Card, UPI, Mobile Wallets with split payment support
- Order Park & Reopen — hold active orders without losing cart state
- Thermal ESC/POS receipt printing over TCP/IP + PDF invoice preview

### 2. 🪑 Interactive Table Management & Reservations
- Visual floor plan grid with 10 color-coded real-time table statuses
- Sections/Zones: Main Hall, AC Room, Terrace, Bar, Private Dining, Banquet
- 24-hour visual booking time grid with collision detection
- Reservation management: Pending → Confirmed → Seated → Cancelled workflow
- Staff assignment: Designate waiters to tables with 1-tap selection
- Active Hold Orders hub: Centralized parked order management

### 3. 👨‍🍳 Kitchen Display System (KDS) & KOT Management
- Paperless digital KOTs auto-dispatched on order placement
- Live WebSocket push with 10-second fallback polling heartbeat
- Full lifecycle tracking: Pending → Cooking → Ready → Served
- Kitchen station routing: Chinese, Tandoor, Fast Food, Main Course, Bakery, Beverages
- Smart ticket sorting: Oldest First, Priority/Urgent, Table Number, Fastest Prep
- Automated delay alerts with reason capture (audit-ready)
- Chef assignment, speed metrics, and kitchen history archive

### 4. 📱 Waiter Mobile & Tablet Ordering
- Handheld-optimized floor plan for smartphones and tablets
- 1-tap table selection → guest count → staff assignment → order flow
- Digital menu with category carousel, instant search, and dietary badges
- Item customization: Dietary preference, spice level, and cooking instructions
- Sliding cart drawer with 1-tap KOT firing directly to the kitchen

### 5. 🌐 Customer Self-Ordering (Local LAN Web Server)
- Zero-install web ordering via embedded Shelf HTTP server on port `8080`
- Table-specific QR codes: `http://<LAN-IP>:8080/menu?table=<ID>`
- Vanilla HTML/CSS/JS frontend — customers order from their phone browser
- Real-time WebSocket sync: Web orders appear instantly on POS & kitchen screens
- Works entirely offline — no internet required, only local restaurant Wi-Fi

### 6. 📋 Menu, Recipe & Dietary Management
- Full menu catalog: Items, categories, pricing, GST slabs, veg/non-veg status
- Dietary tags: Pure Jain, Semi Jain, Vegan, Gluten-Free
- Taste ratings: Sweet, Mild, Spicy, Extra Spicy, Tangy
- Promotional badges: Chef's Special, Best Seller, New, Seasonal, Recommended
- Recipe (BOM) mapping: Link menu items → raw ingredients for auto stock deduction
- Cooking metadata: Prep time, cook time, portion size, difficulty, step-by-step instructions
- In-app training video playback (local & external URL support)

### 7. 📦 Inventory, Stock & Vendor Management
- Real-time stock tracking with Healthy / Low Stock / Out of Stock status indicators
- Configurable low-stock thresholds and perishable expiry date tracking (FEFO)
- UOM support: Kg, Gram, Liter, mL, Pieces, Packs, Boxes, Crates
- Vendor & supplier directory with contact profiles and ingredient linkage

### 8. ⏱️ Live Operations Tracking & Audit Trail
- Real-time active order progress monitoring across all channels
- Immutable `order_status_logs` table: every state transition with staff and timestamp
- KPIs: Average prep time, delayed orders counter, chef speed metrics
- Peak dining hour analysis for staffing optimization

### 9. 📊 Analytics, Financial Reporting & Accounting
- Executive dashboard: Daily revenue, table occupancy, active orders, stock alerts
- Sales & revenue breakdown by date range, payment mode, and order type
- Product performance: Top sellers, revenue contributors, slow-moving items
- Chef & kitchen productivity: Ticket counts, average speed, delay rates per station
- Full P&L ledger: Gross sales, expenses, tax liabilities, net operating balance
- Expense management: Categorized operational costs with date filtering
- Complete order history with multi-parameter filtering and invoice re-printing

### 10. 🏢 Multi-Branch, RBAC & System Administration
- Multi-restaurant / multi-branch with database-level data isolation (`restaurant_id`)
- Role-Based Access Control: Admin, Manager, Cashier, Waiter, Chef
- Staff profiles: Contact details, shift assignment, active/inactive toggle
- Password hashing with crypto-secure storage
- SQLite database 1-click backup, export, and safe restore
- Thermal printer configuration: IP, port, ESC/POS layout settings
- Configurable GST slabs, waiter/chef assignment toggles

---

## 🔄 Project Flow

### Full Order Lifecycle

```
APPLICATION STARTUP
  DB Init → Restaurant Selection → Login (RBAC) → Role-based Dashboard
      │
      ├─── POS Terminal ──┐
      ├─── Waiter Tablet ─┼── ORDER CREATION
      └─── Customer QR ───┘
                │
                ▼
        Select Table / Order Type
        → Add Items to Cart
        → Apply Discounts & Notes
        → Set Guest Count
        → Assign Waiter / Chef
        → Confirm Order
                │
                ▼
        SQLite Write + KOT Created
                │
         WebSocket Broadcast
          ┌────┴────────────────────┐
          ▼                         ▼
   Table Status              Kitchen Display System
   Auto-Updated                   │
   (Ordering →           Pending → Chef Accepts
    Preparing)           → Cooking → Food Ready
                         → Alert Waiter → Served
                │
                ▼
        BILLING & SETTLEMENT
        Guest Requests Bill → POS Generates Invoice
        → Select Payment Mode (Cash / Card / UPI / Wallet)
        → Record Payment → Print Thermal Receipt / PDF
        → Mark Order Paid → Table → Cleaning
                │
          ┌─────┴──────────────────┐
          ▼                         ▼
  Inventory Auto-Deduction    Analytics & Reporting
  (via recipe BOM)            (P&L, Sales, Chef Metrics)
```

### User Role Flow

```
Admin
 ├── Full system access
 ├── User management & RBAC
 ├── Multi-branch configuration
 ├── Database backup & restore
 └── Financial reports & P&L

Manager
 ├── POS, Table, Reservations
 ├── Menu & Recipe management
 ├── Inventory & Vendor management
 └── Analytics dashboard

Cashier
 ├── POS billing terminal
 ├── Active table view
 ├── Order settlement
 └── Receipt printing

Waiter
 ├── Handheld floor plan
 ├── Table-side ordering
 └── KOT firing

Chef
 ├── Kitchen Display System
 ├── KOT status updates
 └── Cooking timers
```

### WebSocket Real-Time Sync Flow

```
POS Terminal — Shelf Server (Host · port 8080)
    │
    ├── WebSocket Broadcast
    │
    ├──► Kitchen Screen (KDS)  — receives new KOTs instantly
    ├──► Waiter Tablets        — table status updates
    └──► Customer Browsers     — order confirmation (QR self-ordering)
```

---

## 🗂️ Project Structure

```
26_2_DineMaster/
├── lib/
│   ├── core/
│   │   └── database/         # DatabaseHelper — schema, migrations, queries
│   ├── models/               # Dart data models (UserModel, TableModel, ProductModel, OrderModel)
│   ├── repositories/         # Repository layer — data access abstraction
│   ├── screens/              # All UI screens
│   │   ├── auth/             # Login screen
│   │   ├── dashboard/        # Executive dashboard
│   │   ├── pos/              # POS billing terminal
│   │   ├── tables/           # Table management & floor plan
│   │   ├── kitchen/          # Kitchen Display System (KDS)
│   │   ├── waiter/           # Waiter handheld interface
│   │   ├── menu/             # Menu catalog & recipe management
│   │   ├── inventory/        # Stock & vendor management
│   │   ├── analytics/        # Reports & analytics
│   │   ├── accounting/       # Financial ledger & expenses
│   │   ├── settings/         # System & hardware configuration
│   │   └── admin/            # User management & RBAC
│   ├── services/             # Background services (Shelf server, WebSocket)
│   ├── widgets/              # Shared reusable UI components
│   └── main.dart             # App entry point, GoRouter configuration
├── assets/
│   └── images/logo.jpg       # Application logo
├── android/                  # Android-specific configuration
├── ios/                      # iOS-specific configuration
├── macos/                    # macOS-specific configuration
├── windows/                  # Windows-specific configuration
├── linux/                    # Linux-specific configuration
├── web/                      # Web platform files
├── test/                     # Unit & widget tests
├── .github/workflows/        # GitHub Actions CI/CD pipelines
│   ├── pull_request.yml      # PR validation pipeline
│   ├── release.yml           # Release build & publish pipeline
│   ├── validate.yml          # Reusable: analyze + test
│   └── build.yml             # Reusable: multi-platform build
├── pubspec.yaml              # Flutter dependencies & assets
├── analysis_options.yaml     # Dart lint configuration
├── database.md               # SQLite schema reference
├── features.md               # Exhaustive feature specification
├── dev.md                    # This document
├── assemble.py               # Build assembly utility script
├── fix_types.py              # Type fix utility script
└── update_cart.py            # Cart update utility script
```

---

## 🗄️ Database Schema Overview

The application uses **SQLite** (`sqflite` / `sqflite_common_ffi`) with the following core tables:

| Table | Purpose |
|-------|---------|
| `restaurants` | Multi-branch restaurant profiles |
| `users` | Staff accounts with roles and hashed passwords |
| `customers` | Customer profiles with loyalty points |
| `tables` | Restaurant table layout, status, and section |
| `categories` | Menu category organization |
| `products` | Menu items with pricing, dietary tags, and recipe data |
| `orders` | Customer order records across all channels |
| `order_items` | Individual line items per order |
| `kot` | Kitchen Order Tickets with lifecycle timestamps |
| `order_status_logs` | Immutable audit trail of all order state changes |
| `payments` | Payment transaction records |
| `bookings` | Table reservations and booking management |
| `ingredients` | Raw kitchen ingredient master |
| `recipes` | BOM mapping: menu items → ingredients + quantities |
| `inventory` | Stock levels, thresholds, and expiry tracking |
| `suppliers` / `vendors` | Vendor/supplier directory |
| `expenses` | Operational expense categorization |
| `offers` | Promotional discount codes |
| `loyalty_transactions` | Customer loyalty point earn/redeem ledger |

> Full schema with column types, constraints, and descriptions: [database.md](database.md)

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, `^3.11.1`)
- [Java 21 JDK](https://www.oracle.com/java/technologies/downloads/) (for Spring Boot backend)
- [PostgreSQL](https://www.postgresql.org/) (optional for local standalone, required for backend PostgreSQL profile)
- **Windows builds**: Visual Studio with C++ Desktop workload
- **Android builds**: Android SDK & `adb`
- **iOS/macOS builds**: macOS + Xcode
- **Linux builds**: GTK 3 headers (`libgtk-3-dev`, `ninja-build`)

### Setup & Run — Flutter Frontend

```bash
# 1. Switch to frontend directory
cd frontend

# 2. Configure environment
# Windows CMD:
copy .env.example .env
# PowerShell / Bash:
cp .env.example .env

# 3. Install dependencies
flutter pub get

# 4. Run on connected device / desktop
flutter run
# Note: App starts a local Shelf server on port 8080 at launch
```

### Setup & Run — Spring Boot Backend

```bash
# 1. Switch to backend directory
cd backend

# 2. Configure environment
# Windows CMD:
copy .env.example .env
# PowerShell / Bash:
cp .env.example .env


# 3. Run with Maven Wrapper
.\mvnw.cmd spring-boot:run     # Windows PowerShell
./mvnw spring-boot:run         # Linux / macOS

# 4. Or build and run standalone JAR
.\mvnw.cmd clean package -DskipTests
java -jar target/dinemaster-backend-1.0.0.jar
# Backend will be active on http://localhost:8081
```

### Build Commands

| Target | Platform | Command |
|--------|----------|---------|
| Frontend | Windows | `cd frontend && flutter build windows --release` |
| Frontend | macOS | `cd frontend && flutter build macos --release` |
| Frontend | Linux | `cd frontend && flutter build linux --release` |
| Frontend | Android | `cd frontend && flutter build apk --release` |
| Frontend | iOS | `cd frontend && flutter build ios --release` |
| Frontend | Web | `cd frontend && flutter build web --release` |
| Backend | JAR (Fat JAR) | `cd backend && .\mvnw.cmd clean package` |

### Testing & Validation

```bash
# Frontend static analysis
cd frontend && dart analyze --fatal-warnings

# Frontend unit & widget tests (all 41 tests)
cd frontend && flutter test

# Backend automated test suite (Spring Boot + JPA + Services)
cd backend && .\mvnw.cmd test
```

---

## 🔭 Project Future Scope

### Phase 2 — Enhanced Customer Experience
- **Loyalty & Rewards Program**: Points-based rewards with redemption on billing, birthday/anniversary special discounts
- **Customer Mobile App**: Dedicated iOS/Android app for pre-ordering, reservation booking, and order tracking
- **Online Ordering Integration**: Plug-in adapters for Swiggy, Zomato, and restaurant's own website ordering portal
- **Customer Feedback & Rating System**: Post-meal digital feedback with star ratings per dish

### Phase 3 — Advanced Kitchen & Operations
- **AI-Powered Demand Forecasting**: Predict daily ingredient needs based on historical order patterns to minimize wastage
- **Smart Inventory Auto-Replenishment**: Automatic low-stock purchase order generation and emailing to suppliers
- **Allergen Compliance Engine**: Cross-check customer dietary restrictions against item ingredients before order confirmation
- **KDS Voice Announcements**: Text-to-speech audio alerts for kitchen staff when orders are placed or urgency escalates

### Phase 4 — Business Intelligence & Cloud
- **Cloud Sync & Dashboard**: Optional cloud backend (Firebase / Supabase) for remote monitoring and consolidated multi-branch reporting
- **Multi-Device Real-Time Sync via Cloud**: Backup WebSocket channels over cloud for large or multi-floor setups
- **Advanced Analytics Suite**: ML-powered insights — peak hour prediction, menu optimization, staff performance benchmarking
- **Business Comparison Reports**: Branch vs. branch performance comparison for chain restaurant owners

### Phase 5 — Integrations & Ecosystem
- **Tally / Accounting Software Integration**: Export financial data directly to Tally ERP or QuickBooks
- **Payment Gateway Integration**: Full POS-embedded UPI, Razorpay, and Stripe payment terminal support
- **Biometric Attendance Integration**: Staff check-in/out via fingerprint or face ID linked to shift management
- **Digital Menu Boards**: Live menu updates pushed to restaurant TV displays via HDMI or Chromecast
- **Multi-Language Support (i18n)**: Regional language menus (Hindi, Tamil, Telugu, Kannada) for staff and customer interfaces

### Phase 6 — Scalability & Enterprise
- **SaaS Multi-Tenancy**: Convert to a hosted SaaS solution with tenant isolation, subscription billing, and white-labeling
- **Franchise Management Module**: Centralized control panel for franchise owners with royalty tracking and compliance auditing
- **Food Safety & HACCP Compliance Module**: Digital HACCP checklists, temperature logs, and health inspection reports
- **Third-Party Hardware Support**: Integration with weighing scales, cash drawers, and customer-facing display poles (CFD)

---

## 📋 Versioning & Release

The project follows **`Major.Minor.Patch`** semantic versioning. Current version: **`1.0.0+1`** (defined in `pubspec.yaml`).

```bash
# Tag and release
git tag v1.0.0
git push origin v1.0.0
# Triggers release.yml: analyze → test → build all platforms → GitHub Release
```

---

*DineMaster — KOS Restaurant ERP & POS System · All rights reserved.*
