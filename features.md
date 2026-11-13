# DineMaster — Complete Features & Subfeatures Specification

DineMaster (KOS) is an enterprise-grade Restaurant ERP, Point of Sale (POS), and Kitchen Display Management System built with Flutter, SQLite, and an embedded Shelf local networking server. This document provides an exhaustive, granular breakdown of every module, feature, and subfeature implemented across the platform.

---

## Table of Contents
1. [Point of Sale (POS) & Billing Terminal](#1-point-of-sale-pos--billing-terminal)
2. [Interactive Table Management & Floor Plan](#2-interactive-table-management--floor-plan)
3. [Reservation & Booking Time Grid](#3-reservation--booking-time-grid)
4. [Kitchen Display System (KDS) & KOT Management](#4-kitchen-display-system-kds--kot-management)
5. [Waiter Mobile & Tablet Ordering Interface](#5-waiter-mobile--tablet-ordering-interface)
6. [Customer Self-Ordering & Local LAN Web Server](#6-customer-self-ordering--local-lan-web-server)
7. [Menu Catalog & Dietary Attribute Management](#7-menu-catalog--dietary-attribute-management)
8. [Recipe Management & Production Costing](#8-recipe-management--production-costing)
9. [Inventory, Stock & Vendor Management](#9-inventory-stock--vendor-management)
10. [Live Operations Tracking & Audit Trail](#10-live-operations-tracking--audit-trail)
11. [Analytics & Business Intelligence](#11-analytics--business-intelligence)
12. [Financial Accounting, Expenses & Order History](#12-financial-accounting-expenses--order-history)
13. [User Management & Role-Based Access Control (RBAC)](#13-user-management--role-based-access-control-rbac)
14. [Multi-Restaurant & Branch Management](#14-multi-restaurant--branch-management)
15. [System Settings & Hardware Integrations](#15-system-settings--hardware-integrations)
16. [Cross-Platform Architecture & Technical Foundations](#16-cross-platform-architecture--technical-foundations)

---

## 1. Point of Sale (POS) & Billing Terminal

The POS terminal serves as the central high-speed checkout and order creation hub, optimized for fast-paced dining environments with touchscreen, mouse, and keyboard shortcut support.

### 1.1 Multi-Channel Order Placement
- **Dine-In Orders**: Direct table association with real-time floor plan binding.
- **Table Orders**: Dedicated table-side orders with waiter and guest count tracking.
- **Takeaway / Carry-Out**: Express ordering without table allocation.
- **Delivery Orders**: Customer address, phone number, and delivery agent assignment.
- **Online Orders**: Integration ready for web-originating orders.
- **Walk-in Customers**: Quick-counter checkout with default walking customer profiles.

### 1.2 Cart & Item Management
- **Instant Product Search**: Filter catalog instantly by keyword, SKU, or attribute.
- **Category Navigation**: Fast category switches (Starters, Main Course, Breads, Beverages, Desserts).
- **Quantity Adjustments**: 1-tap increment/decrement with numerical entry support.
- **Item-Level Special Notes**: Custom preparation notes attached to individual dishes.
- **Item Removal & Cart Clearing**: Confirmation guarded cart reset and item deletion.
- **Visual Food Attributes**: Immediate indicators for Veg, Non-Veg, Vegan, Jain, and Chef Specials.

### 1.3 Pricing, Taxes & Discount Engine
- **Itemized Subtotal**: Dynamic real-time calculation of all cart items.
- **Multi-Slab GST Tax Calculation**: Automated tax computation based on individual product GST rates (default 5.0%, configurable up to 18%+).
- **Flexible Discounts**:
  - **Flat Amount Discount**: Currency deduction directly from the bill total.
  - **Percentage Discount**: Dynamic percentage deduction computed against the subtotal.
  - Custom discount remarks and audit reason capture.
- **Final Net Total**: Live display of Subtotal + Tax - Discounts.

### 1.4 Payment Settlement & Tendering
- **Multiple Payment Modes**:
  - Cash (with tender amount calculation and change returned).
  - Credit / Debit Card.
  - UPI / QR Code Digital Payments.
  - Mobile Wallets.
  - Split Payment support across payment modes.
- **Payment Status Tracking**: Live switching between `Unpaid`, `Partially Paid`, and `Paid`.
- **Payment Timestamps**: Stamped transaction records stored in the SQLite `payments` ledger.

### 1.5 Order Lifecycle & Hold/Reopen Mechanism
- **Park / Hold Orders**: Temporarily pause an active transaction without losing customer items to service the next diner.
- **Active Hold Orders Manager**: View all parked tabs with elapsed time badges.
- **Reopen & Edit Orders**: Recall any active or held order by `orderId` or `tableId` directly into the POS cart to append new dishes or finalize payment.
- **Order Cancellation**: Cancel active orders with inventory reversal safeguards.

### 1.6 Thermal Receipt & Invoice Generation
- **ESC/POS Thermal Printing**: Direct output to 80mm / 58mm network thermal printers over TCP/IP.
- **PDF Invoice Generation**: Standardized clean invoice layout including:
  - Restaurant business name, address, contact, and GSTIN.
  - Invoice number and date/time stamp.
  - Table number, order type, and server name.
  - Itemized quantity, rate, tax, and total breakdown.
  - Payment mode details and thank-you footer.
- **In-App PDF Preview**: Built-in PDF print preview screen prior to physical printing.

---

## 2. Interactive Table Management & Floor Plan

An interactive floor layout that gives hosts and cashiers instant visibility into the physical dining room state.

### 2.1 Table Layout Grid View
- **Interactive Visual Cards**: Responsive grid depicting all restaurant tables with seating capacity and real-time status.
- **Color-Coded Status System**:
  - `Available` (Green): Open and ready for guests.
  - `Occupied` (Blue): Guests currently seated and ordering.
  - `Reserved` (Orange): Booked for upcoming guests.
  - `Ordering` (Amber): Guests actively browsing or placing orders.
  - `Preparing` (Purple): Food is actively being prepared in the kitchen.
  - `Bill Requested` (Yellow): Guests requested check/invoice.
  - `Payment Pending` (Pink): Bill printed, waiting for payment settlement.
  - `Paid` (Teal): Payment received, awaiting guest departure.
  - `Cleaning` (Grey): Table cleared, undergoing sanitization.
  - `Out of Service` (Red): Maintenance or offline.
- **Quick Table Card Actions**:
  - 1-tap to start new order on available tables.
  - View existing order and current bill total on occupied tables.
  - Manually override table status.
  - Assign designated waiter from a dropdown.

### 2.2 Dining Room Sections & Zones
- **Zone Grouping**: Categorize dining spaces into customized zones:
  - Main Dining Hall
  - AC Family Room
  - Outdoor Patio / Terrace
  - Bar & Lounge
  - Private Dining Rooms (PDR)
  - Banquet Hall
- **Section Filtering**: Filter tables by specific sections or view all at once.

### 2.3 Table Configuration & Layout Customization
- **Table Configuration Dialog**:
  - Table identifier / number (e.g., T1, T2, P1).
  - Custom display name (e.g., "Window Corner", "Booth 4").
  - Seating capacity (1 to 20+ guests).
  - Assigned dining section.
  - Table type classification (Standard Table, Booth, Bar Counter, High Top, Lounge).
  - Reservable toggle (Enable/disable for reservations).
  - Operational notes and table status remarks.
  - Active/Inactive toggle.

---

## 3. Reservation & Booking Time Grid

A complete table reservation suite that prevents double-bookings and organizes advance guest scheduling.

### 3.1 24-Hour Booking Time Grid Tab
- **Visual Hourly Time Slots**: Full 24-hour visual timeline split into 1-hour slots.
- **Table-First Selection**: Select any table to inspect its full-day schedule.
- **Real-Time Collision Detection**: Prevents double-booking table slots at overlapping times.
- **Date Picker Navigation**: Browse reservations across past, present, and future dates.
- **Direct Slot Booking**: Tap an available time slot to open a pre-filled booking modal for that exact table and hour.

### 3.2 Booked / Reserved Management Tab
- **Comprehensive Reservation Ledger**: List of all bookings sorted chronologically.
- **Guest Profile Details**:
  - Customer name and contact phone number.
  - Expected guest headcount.
  - Reserved table number and section.
  - Booking time and duration.
  - Dietary requirements and special anniversary/birthday notes.
- **Booking Status Workflow**:
  - `Pending`: Reservation requested.
  - `Confirmed`: Confirmed by staff.
  - `Seated / Checked-In`: Guests arrived, automatically updating table status to Occupied.
  - `Cancelled`: Reservation released, restoring table availability.

### 3.3 Active Hold Orders Tab
- **Parked Bills Hub**: Unified tab displaying all orders placed on hold across all dining tables.
- **Key Metrics**: Table number, order elapsed time, item count, and subtotal.
- **Fast Resume**: 1-tap transfer back into POS for instant checkout.

---

## 4. Kitchen Display System (KDS) & KOT Management

A paperless Kitchen Display System that bridges waitstaff, POS terminals, and kitchen line cooks in real time.

### 4.1 Digital Kitchen Order Tickets (KOT)
- **Automatic Ticket Dispatch**: Orders placed on POS or waiter tablets appear immediately on kitchen screens.
- **Generated KOT Numbers**: Unique sequential identifiers per kitchen ticket.
- **Item Breakdown**: Item name, quantity, cooking notes, and dietary tags.
- **Visual Urgent/Priority Badges**: Highlights high-priority or VIP orders.

### 4.2 Real-Time WebSocket Synchronization
- **Zero-Latency Push**: Local WebSocket events broadcast instantly across all LAN devices.
- **Fallback Polling Engine**: 10-second background heartbeat ensures no missed tickets even under packet drop.

### 4.3 Order Fulfillment Lifecycle
- **Step 1: Pending**: New ticket arrived; waiting for line cook acceptance.
- **Step 2: Preparing / Cooking**: Chef started preparation; timestamp logged (`started_cooking_at`).
- **Step 3: Ready**: Food cooked and plated; timestamp logged (`ready_at`). Kitchen sends alert to waitstaff.
- **Step 4: Served**: Waiter delivered food to table; timestamp logged (`served_at`). Ticket archived.

### 4.4 Kitchen Station Routing
- **Filter by Cooking Station**:
  - Chinese / Wok Station
  - Tandoor & Grill Station
  - Fast Food & Fryer
  - Main Course / Curry Station
  - Bakery & Desserts
  - Beverages & Bar
- **All Stations Overview**: Head chef master display view.

### 4.5 Intelligent Ticket Sorting
- **Oldest First**: Standard FIFO (First In, First Out) kitchen discipline.
- **Priority / Urgent**: Floats high-priority and rush orders to the top.
- **Table Number**: Groups tickets by dining table for consolidated cooking.
- **Fastest Prep**: Prioritizes quick turnaround appetizers and drinks.

### 4.6 Automated Delay Detection & Prompting
- **Target Preparation Timers**: Dynamic countdown based on estimated prep time (default 15 minutes).
- **Auto Delay Warning**: Visual color shifting when prep time exceeds thresholds.
- **Delay Reason Prompting Modal**: Automatic prompt for kitchen staff to categorize delays:
  - High kitchen load / rush hour
  - Raw ingredient restocking
  - Complex custom dietary preparation
  - Equipment maintenance
- **Audit Logging**: Recorded into `kot.delay_reason` for kitchen efficiency analysis.

### 4.7 Kitchen Archive & Chef Metrics
- **Completed History View**: Historical log of served KOTs with start, ready, and served timestamps.
- **Assigned Chef Tracking**: Chef name tagged per ticket for individual accountability.

---

## 5. Waiter Mobile & Tablet Ordering Interface

A handheld-optimized interface tailored for waiters taking table-side orders on mobile phones and tablets.

### 5.1 Mobile Floor Plan View
- **Compact Layout**: High-density touch-friendly cards showing table number, capacity, and live status.
- **Filter Pills**: Fast filtering by section (Main Hall, AC, Terrace) and status (Available, Occupied, Reserved).
- **Occupied Table Overview**: Shows currently seated time, assigned waiter, and current cart value.

### 5.2 Table-Side Order Taking
- **1-Tap Table Selection**: Select table and immediately launch ordering flow.
- **Guest Headcount Input**: Record the number of dining guests.
- **Staff Assignment**: Designate waiter name and target line chef.
- **Customer Lookup**: Fast customer name and phone entry for loyalty tracking.

### 5.3 Digital Menu Navigation
- **Horizontal Category Carousel**: Quick jumping across Starters, Main Course, Breads, Beverages, and Desserts.
- **Instant Search**: Real-time product search bar.
- **Food Attributes Badging**: Instant visual verification of Pure Jain, Semi Jain, Vegan, and spice ratings.

### 5.4 Item Customization Dialog
- **Dietary Preference Selection**: Choose between Regular, Pure Jain, Semi Jain, Vegan, or Gluten-Free.
- **Spice Level Selector**:
  - Mild
  - Sweet
  - Spicy
  - Extra Spicy
- **Custom Cooking Instructions**: Free-form text for allergies (e.g., "no peanuts", "extra crispy").

### 5.5 Waiter Cart Panel & 1-Tap KOT Firing
- **Sliding Cart Drawer**: Compact slide-in cart previewing items, quantities, and customizations.
- **Quantity Adjuster**: 1-tap +/- buttons.
- **Direct KOT Submission**: 1-tap "Fire KOT" button that immediately prints/pushes ticket to the kitchen and sets table status to `Ordering` / `Preparing`.

---

## 6. Customer Self-Ordering & Local LAN Web Server

An embedded local server providing diners with app-less digital web ordering directly from their personal mobile devices.

### 6.1 Embedded Shelf HTTP & WebSocket Server
- **Zero Cloud Dependency**: Runs locally inside the DineMaster Flutter desktop or Android host application on port `8080`.
- **Offline Reliability**: Continues functioning during internet outages as long as local Wi-Fi is operational.
- **Automatic Server Startup**: Initializes automatically on application launch.

### 6.2 QR Code Digital Menu (`/menu`)
- **Table-Specific QR Codes**: Diners scan a physical QR code at their table containing `http://<LAN-IP>:8080/menu?table=<ID>`.
- **Lightweight Responsive Web App**: Pure vanilla HTML/CSS/JS frontend rendered directly by Shelf with zero external dependencies.
- **Interactive Menu Browsing**: Categorized dishes with photos, descriptions, prices, and dietary indicators.

### 6.3 Customer Digital Cart & Self-Checkout
- **Live In-Browser Cart**: Customers add items, select quantities, and view cart totals.
- **Special Cooking Requests**: Diners can enter notes directly into the web form.
- **Order Placement (`/api/order`)**: Submits order directly to the DineMaster database.
- **Instant Terminal Sync**: WebSocket broadcasts new web orders directly to POS and kitchen terminals in real time.

---

## 7. Menu Catalog & Dietary Attribute Management

A menu management system supporting rich culinary attributes, dietary classifications, and pricing structures.

### 7.1 Product Catalog Administration
- **Product Fields**:
  - Name, category, description, and item image path.
  - Selling price and cost price.
  - Tax slab (GST percentage: 0%, 5%, 12%, 18%).
  - Food classification: Veg vs. Non-Veg.
  - Availability toggle (Instantly mark items In Stock / Out of Stock).
- **Category Management**: Create, edit, and organize menu categories with custom display ordering.

### 7.2 Dietary Badging System
- **Pure Jain**: Guaranteed no onion, garlic, or root vegetables.
- **Semi Jain**: Customized Jain-friendly variants.
- **Vegan**: 100% plant-based with no dairy or animal products.
- **Gluten-Free**: Safe for celiac and gluten-sensitive diners.
- **Custom Dietary Notes**: Dedicated allergy alerts and preparation precautions.

### 7.3 Taste Preferences & Flavor Profiles
- **Taste Rating**: Sweet, Mild, Medium Spicy, Spicy, Extra Spicy, Tangy.
- **Visual Indicators**: Color-coded chili and flavor icons displayed on POS cards, waiter screens, and customer menus.

### 7.4 Promotional Highlights & Merchandising
- **Badges**:
  - *Chef's Special*
  - *Best Seller*
  - *New Addition*
  - *Seasonal*
  - *Recommended*

### 7.5 Interactive Menu Card Showcase (`menu_card_screen.dart`)
- **Digital Showcase**: High-resolution catalog view designed for customer tablets or counter displays.
- **Attribute Filtering**: Filter menu by dietary badges or taste preferences with one click.

---

## 8. Recipe Management & Production Costing

Connects front-of-house menu sales with back-of-house raw inventory to automate portion control and stock deductions.

### 8.1 Ingredient Recipe Mapping
- **Bill of Materials (BOM)**: Link menu items to raw inventory ingredients.
- **Quantity Used per Portion**: Specify exact grams, milliliters, or units deducted per dish ordered.
- **Automated Inventory Deduction**: Placing or serving an order deducts mapped raw materials from the database in real time.

### 8.2 Cooking Metadata & Preparation Details
- **Prep Time**: Preparation duration in minutes.
- **Cook Time**: Active cooking duration in minutes.
- **Portion Servings**: Number of standard portions yielded per recipe batch.
- **Difficulty Rating**: Easy, Medium, Hard.
- **Step-by-Step Instructions**: Chronological cooking procedure steps for kitchen staff training.

### 8.3 Integrated Culinary Video Tutorials
- **Embedded Video Player**: Local video playback via `video_player` plugin.
- **External Video Links**: Open external culinary training videos via URL launcher.
- **Standard Operating Procedures (SOP)**: On-demand reference for kitchen staff to maintain plating and recipe consistency.

---

## 9. Inventory, Stock & Vendor Management

Supply chain and stockroom tracking to control food wastage, manage shortages, and automate procurement.

### 9.1 Real-Time Stock Tracking
- **Inventory Item Ledger**: Item name, category, current balance, and unit of measurement.
- **Supported Units of Measurement (UOM)**:
  - Kilograms (Kg) / Grams (g)
  - Liters (L) / Milliliters (ml)
  - Pieces (Pcs) / Units
  - Packs / Boxes / Crates
- **Stock Health Status**:
  - `Healthy`: Stock comfortably above safety threshold.
  - `Low Stock`: Current stock at or below configured warning threshold.
  - `Out of Stock`: Zero stock available; triggers warning alerts on POS and menu screens.

### 9.2 Alerts & Expiry Monitoring
- **Configurable Low-Stock Thresholds**: Custom minimum stock levels set per item.
- **Perishable Expiry Date Tracking**: Optional expiry date logging to enforce First-Expired, First-Out (FEFO) stock rotation.

### 9.3 Vendor & Supplier Directory
- **Vendor Profiles**: Vendor business name, contact person, telephone, email, and physical warehouse address.
- **Supplier Linkage**: Map specific ingredients and packaging to designated suppliers.

---

## 10. Live Operations Tracking & Audit Trail

A command-center view of restaurant throughput, operational bottlenecks, and staff actions.

### 10.1 Live Order Progress Timeline
- **Real-Time Active Orders**: Track active orders across all channels (Dine-In, Takeaway, Web).
- **Status Progression**: Live updates across Received ➔ Cooking ➔ Ready ➔ Served ➔ Billed.

### 10.2 Comprehensive Audit Logging (`order_status_logs`)
- **Immutable Log Ledger**: Every state transition is recorded in SQLite with:
  - Order ID
  - Old status ➔ New status
  - Timestamp (`changed_at`)
  - Staff member responsible (`changed_by`)
  - Operational remarks / cancellation reasons

### 10.3 Operations KPIs & Bottleneck Analysis
- **Average Prep Time**: Dynamic calculation of average kitchen ticket completion time.
- **Delayed Orders Counter**: Number of tickets exceeding target preparation durations.
- **Chef Speed & Efficiency**: Individual chef metrics measuring average time per completed dish.
- **Peak Dining Hours**: Analysis of hourly order volume to optimize kitchen staffing.

---

## 11. Analytics & Business Intelligence

A reporting engine providing business intelligence for restaurant owners and general managers.

### 11.1 Executive Overview
- Total gross revenue (Paid orders).
- Total order count and average bill size.
- Live occupied tables vs. total capacity.
- Active held orders count.
- Current low-stock ingredient alert count.

### 11.2 Sales & Revenue Analysis (Tab 1)
- Historical sales trends aggregated by day, week, month, or custom date ranges.
- Average daily revenue and transaction volume.

### 11.3 Product Performance & Menu Engineering (Tab 2)
- Best-selling dishes ranked by sales volume.
- Revenue contributors ranked by gross sales value.
- Slow-moving dishes identified for menu revision or promotional discounts.

### 11.4 Chef & Kitchen Productivity (Tab 3)
- Fulfilled ticket counts per chef.
- Average preparation speed per chef.
- Delay rates per culinary station.

### 11.5 Inventory & Payment Insights (Tab 4)
- Critical low-stock ingredients overview.
- Revenue breakdown by menu category (Starters, Main Course, Beverages, etc.).
- Payment channel distribution (Cash vs. Credit Card vs. UPI vs. Mobile Wallets).

---

## 12. Financial Accounting, Expenses & Order History

Comprehensive ledger tracking revenue, operational overhead, tax obligations, and historical sales receipts.

### 12.1 Profit & Loss (P&L) Ledger
- **Total Gross Sales**: Sum of all paid customer orders.
- **Total Operational Expenses**: Sum of all recorded business overheads.
- **Total Collected Taxes**: Accrued GST collected on behalf of tax authorities.
- **Net Operating Balance**: Gross Sales - Expenses - Tax liabilities.
- **Date Range Filters**: Filter financial statements by Day, Week, Month, Quarter, or Custom Range.

### 12.2 Expense Management
- **Expense Logging**: Add operational expenditures with date, amount, description, and payment method.
- **Expense Categories**:
  - Raw material procurement & groceries
  - Kitchen utilities (Gas, Water, Electricity)
  - Rent & facility maintenance
  - Staff wages & payroll
  - Packaging & disposables
  - Marketing & promotions

### 12.3 Complete Order History (`orders_history_screen.dart`)
- **Historical Order Search**: Searchable database of all historical orders.
- **Multi-Parameter Filtering**:
  - Date range filter (default: last 30 days)
  - Order type (Dine-In, Table Order, Takeaway, Delivery, Online, Walk-in)
  - Order status (Received, Preparing, Ready, Served, Completed, Held, Cancelled)
  - Payment status (Paid, Unpaid)
- **Detailed Order Inspector**: View individual line items, quantities, applied discounts, customer notes, and staff members.
- **Invoice Re-Printing**: Re-print thermal receipts or export historical PDF invoices at any time.

---

## 13. User Management & Role-Based Access Control (RBAC)

Security and employee administration controlling permissions, visibility, and staff shifts.

### 13.1 Staff Profiles & Credentials
- **User Record**: Full name, unique username, securely hashed password, contact phone/email.
- **Active Status**: 1-tap activation/deactivation of staff accounts.
- **Password Obfuscation**: Secure password entry with visibility toggle.

### 13.2 Role-Based Access Control (RBAC)
- **Admin**: Full, unrestricted access to financial ledgers, system settings, database management, user creation, and configuration.
- **Manager**: Access to POS, table layout, reservations, inventory, menu management, and operational analytics.
- **Cashier**: Access restricted to POS billing terminal, active tables, order settlement, and receipt printing.
- **Waiter**: Access restricted to handheld floor plan, table ordering, customer customization, and KOT dispatch.
- **Chef**: Access restricted to the Kitchen Display System (KDS), cooking timers, and KOT status updates.

### 13.3 Staff Shifts & Scheduling
- **Shift Assignment**: Morning Shift, Afternoon Shift, Evening Shift, Full Day.
- **Real-Time Staff Sync**: Immediate synchronization of user status changes across active terminals via WebSocket.

---

## 14. Multi-Restaurant & Branch Management

Scalable multi-outlet configuration allowing business owners to operate multiple locations from a single software installation.

### 14.1 Branch Management
- **Branch Configuration**: Register multiple restaurant outlets with distinct business names, physical addresses, phone numbers, and GSTIN identifiers.
- **Branch Selection Screen**: Prompt on startup to select the active branch or change branches via the navigation drawer.
- **Data Isolation**: Database queries partitioned by `restaurant_id` ensuring clean separation of orders, tables, inventory, and finances per outlet.

### 14.2 Installation Data Handling & Onboarding
- **Previous Data Detection**: Automatically detects pre-existing databases on new installations or updates.
- **Data Protection Guarantee**:
  - *Keep Data*: Continue with existing restaurant records.
  - *Fresh Start / Archive*: Rather than destructive deletion, existing data is safely backed up and archived with timestamps, preventing accidental loss.

---

## 15. System Settings & Hardware Integrations

Extensive customization and peripheral configuration to tailor DineMaster to any restaurant setup.

### 15.1 Hardware Thermal Printer Configuration
- **Network Printer Setup**: Configure IP address (e.g., `192.168.1.100`) and TCP port (e.g., `9100`).
- **Printer Name Identifier**: Tag individual printers (e.g., "Main Counter Printer", "Kitchen KOT Printer").
- **Direct ESC/POS Driver**: Fast printing directly without third-party print spoolers.

### 15.2 Tax & GST Slabs Configuration
- **Customizable GST Scale**: Configure active tax rates (0%, 5%, 12%, 18%, 28%) applied across the POS catalog.
- **Inclusive / Exclusive Tax Modes**: Flexible tax calculation settings.

### 15.3 Network Clustering & Multi-Device Sync
- **Host Server IP Configuration**: Configure client devices (waiter tablets, kitchen screens) to connect to the host POS server IP address over LAN.
- **Bi-Directional WebSocket Sync**: Real-time event communication between server and client terminals.

### 15.4 Database Backup & Disaster Recovery
- **SQLite Database Backup**: 1-click export and backup of the live `.db` file.
- **Database Restore**: Safe restoration of historical backup archives.

### 15.5 Operational Workflow Settings
- **Waiter Assignment Toggle**: Enable or disable mandatory waiter selection during POS order placement.
- **Chef Assignment Toggle**: Enable or disable mandatory line cook selection during order placement.

### 15.6 Branding & Theming
- **Theme**: Clean Modern Light Theme with gold & navy brand accents.
- **Responsive Layout**: Fluid adaptation across desktop monitors (Windows, Linux, macOS), tablets (iPad, Android), and mobile smartphones.

---

## 16. Cross-Platform Architecture & Technical Foundations

Built on a modern, maintainable, and high-performance technical stack.

### 16.1 Technology Stack Summary
- **UI Framework**: Flutter (Dart ^3.11.1)
- **Database**: SQLite (via `sqflite` on mobile and `sqflite_common_ffi` on desktop)
- **Local HTTP & WebSocket Server**: Shelf & Shelf Router
- **Routing & Navigation**: GoRouter with ShellRoute dashboard structure
- **Document Generation**: `pdf` and `printing` packages
- **Video & Media**: `video_player` and `url_launcher`
- **Animation & Aesthetics**: `flutter_animate` with curated HSL color palettes

### 16.2 Platform Deployment Targets
- **Windows**: Native Win32 desktop application (`.exe`).
- **macOS**: Native desktop application (`.app.zip`).
- **Linux**: GTK 3 desktop application (`.tar.gz`).
- **Android**: Tablet & smartphone application (`.apk`).
- **iOS**: iPhone & iPad application (`.ipa` / TestFlight).
- **Web**: Progressive web dashboard (`build/web`).

---
*DineMaster Documentation — All rights reserved.*
