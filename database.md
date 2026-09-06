# DineMaster Database Schema & UI Models Documentation

This document outlines the database schema configured in `database_helper.dart` and maps them to the corresponding UI models found in the `lib/models/` directory.

## 1. UI Models to Database Mapping

The application uses the following primary Dart models to represent data in the UI.

| Dart Model Class | Primary Database Table | Description |
|-----------------|------------------------|-------------|
| `UserModel` | `users` | Represents system users (Admin, Waiter, Chef, etc.). |
| `TableModel` | `tables` | Represents restaurant tables, their layout section, capacity, and real-time status. |
| `ProductModel` | `products` | Represents the menu items, their pricing, preferences, and attributes. |
| `OrderModel` | `orders`, `order_items` | Represents customer orders, including the selected products, KOT tracking, and billing details. |

*(Note: Other entities such as KOT, Bookings, Categories, and Inventory are currently manipulated as Maps or direct database queries in the codebase, without a dedicated Dart Model class in `lib/models/`)*

---

## 2. Complete Database Schema (SQLite)

The DineMaster application uses SQLite with the following schema setup.

### 2.1 Core Entities

#### `restaurants`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `name` | TEXT | NOT NULL | Name of the restaurant |
| `address` | TEXT | Nullable | Physical address |
| `phone` | TEXT | Nullable | Contact number |
| `created_at` | TEXT | NOT NULL | Creation timestamp |

#### `users` (UserModel)
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `name` | TEXT | NOT NULL | Full name |
| `username` | TEXT | UNIQUE, NOT NULL | Login username |
| `password` | TEXT | NOT NULL | Hashed password |
| `role` | TEXT | NOT NULL | e.g. Admin, Waiter, Chef, Cashier |
| `is_active` | INTEGER | DEFAULT 1 | 1=Active, 0=Inactive |
| `contact_details`| TEXT | Nullable | Contact number/email |
| `shift_timing` | TEXT | Nullable | E.g. "Morning", "Evening" |
| `created_at` | TEXT | NOT NULL | Account creation timestamp |

#### `customers`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `name` | TEXT | NOT NULL | Full name |
| `phone` | TEXT | UNIQUE, NOT NULL | Phone number |
| `email` | TEXT | Nullable | Email address |
| `loyalty_points` | INTEGER | DEFAULT 0 | Accumulated reward points |
| `created_at` | TEXT | NOT NULL | Registration timestamp |

### 2.2 Restaurant Operations

#### `tables` (TableModel)
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `table_number` | TEXT | UNIQUE, NOT NULL | Table identifier (e.g. T1) |
| `name` | TEXT | Nullable | Display name |
| `capacity` | INTEGER | NOT NULL | Seat capacity |
| `status` | TEXT | NOT NULL | Available, Occupied, Reserved, etc. |
| `section` | TEXT | DEFAULT 'Main Hall'| Dining area section |
| `table_type` | TEXT | DEFAULT 'Standard Table' | E.g. Standard, Booth |
| `is_active` | INTEGER | DEFAULT 1 | 1=Active, 0=Inactive |
| `is_reservable` | INTEGER | DEFAULT 1 | 1=Reservable, 0=Not |
| `notes` | TEXT | Nullable | Special instructions |
| `waiter_id` | INTEGER | FOREIGN KEY | Assigned `users.id` |
| `restaurant_id` | INTEGER | FOREIGN KEY | `restaurants.id` |

#### `categories`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `name` | TEXT | UNIQUE, NOT NULL | E.g. Starters, Main Course |
| `restaurant_id` | INTEGER | FOREIGN KEY | `restaurants.id` |

#### `products` (ProductModel)
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `name` | TEXT | NOT NULL | Item name |
| `description` | TEXT | Nullable | Short description |
| `ingredients` | TEXT | Nullable | List of ingredients |
| `price` | REAL | NOT NULL | Selling price |
| `category` | TEXT | NOT NULL | Associated category name |
| `is_veg` | INTEGER | NOT NULL | 1=Veg, 0=Non-Veg |
| `image_path` | TEXT | Nullable | Path to item image |
| `is_available` | INTEGER | DEFAULT 1 | 1=Available, 0=Out of stock |
| `gst_percentage` | REAL | DEFAULT 5.0 | Tax applied |
| `dietary_preferences`| TEXT | Nullable | e.g. Vegan, Gluten-Free |
| `taste_preferences` | TEXT | Nullable | e.g. Spicy, Sweet |
| `attributes` | TEXT | Nullable | e.g. Chef's Special |
| `custom_dietary_notes`| TEXT | Nullable | User notes for allergies |
| `recipe_steps` | TEXT | Nullable | Instructions |
| `prep_time` | INTEGER | Nullable | Preparation time |
| `cook_time` | INTEGER | Nullable | Cooking time |
| `servings` | INTEGER | Nullable | Portion sizes |
| `difficulty` | TEXT | Nullable | E.g. Easy, Medium, Hard |
| `video_path` | TEXT | Nullable | Path to video guide |
| `restaurant_id` | INTEGER | FOREIGN KEY | `restaurants.id` |

### 2.3 Order Management

#### `orders` (OrderModel)
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `table_id` | INTEGER | FOREIGN KEY | `tables.id` |
| `customer_id` | INTEGER | FOREIGN KEY | `customers.id` |
| `waiter_id` | INTEGER | FOREIGN KEY | `users.id` |
| `total_amount` | REAL | NOT NULL | Final bill amount |
| `status` | TEXT | NOT NULL | Received, Preparing, Ready, Served, Completed |
| `type` | TEXT | NOT NULL | Dine-In, Takeaway, Delivery |
| `order_time` | TEXT | NOT NULL | Placement timestamp |
| `notes` | TEXT | Nullable | Special requests |
| `payment_status` | TEXT | DEFAULT 'Unpaid'| Unpaid, Paid |
| `payment_method` | TEXT | Nullable | Cash, Card, UPI |
| `discount_amount` | REAL | DEFAULT 0 | Applied discount |
| `customer_name` | TEXT | Nullable | For Quick Orders |
| `customer_phone` | TEXT | Nullable | For Quick Orders |
| `order_taker_name` | TEXT | Nullable | Name of staff taking order |
| `order_taker_id` | INTEGER | Nullable | ID of staff taking order |
| `delivered_by_name`| TEXT | Nullable | Delivery staff name |
| `delivered_by_id` | INTEGER | Nullable | Delivery staff ID |
| `delivery_timestamp`| TEXT | Nullable | Timestamp of delivery completion |
| `restaurant_id` | INTEGER | FOREIGN KEY | `restaurants.id` |

#### `order_items`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `order_id` | INTEGER | FOREIGN KEY | `orders.id` |
| `product_id` | INTEGER | FOREIGN KEY | `products.id` |
| `quantity` | INTEGER | NOT NULL | Quantity ordered |
| `price` | REAL | NOT NULL | Price at time of order |
| `notes` | TEXT | Nullable | Customization requests |
| `status` | TEXT | NOT NULL | Pending, Cooking, Ready, Served |
| `kot_id` | INTEGER | FOREIGN KEY | Linked `kot.id` |

#### `kot` (Kitchen Order Ticket)
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `order_id` | INTEGER | FOREIGN KEY | `orders.id` |
| `kot_number` | TEXT | NOT NULL | Generated KOT Number |
| `status` | TEXT | NOT NULL | Pending, Cooking, Ready, Served |
| `created_at` | TEXT | NOT NULL | Timestamp |
| `started_cooking_at`| TEXT | Nullable | Timestamp |
| `ready_at` | TEXT | Nullable | Timestamp |
| `served_at` | TEXT | Nullable | Timestamp |
| `delay_reason` | TEXT | Nullable | Explanation for delayed prep |
| `chef_name` | TEXT | Nullable | Assigned Chef |
| `priority` | TEXT | DEFAULT 'Normal'| Normal, High, Urgent |
| `estimated_time` | INTEGER | DEFAULT 15 | Time in minutes |

#### `order_status_logs`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `order_id` | INTEGER | NOT NULL | Linked `orders.id` |
| `status` | TEXT | NOT NULL | The new status applied |
| `changed_at` | TEXT | NOT NULL | Timestamp |
| `changed_by` | TEXT | Nullable | Staff member name |
| `notes` | TEXT | Nullable | Additional remarks |

#### `payments`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `order_id` | INTEGER | FOREIGN KEY | `orders.id` |
| `amount` | REAL | NOT NULL | Settled amount |
| `payment_mode` | TEXT | NOT NULL | Cash, UPI, Card, Wallet |
| `payment_time` | TEXT | NOT NULL | Timestamp |

### 2.4 Inventory and Accounting

#### `ingredients`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `name` | TEXT | NOT NULL | Ingredient Name |
| `unit` | TEXT | NOT NULL | Kg, Gram, Ltr, Pcs |
| `stock_quantity` | REAL | DEFAULT 0 | Available stock |
| `restaurant_id` | INTEGER | FOREIGN KEY | `restaurants.id` |

#### `recipes`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `product_id` | INTEGER | FOREIGN KEY | `products.id` |
| `ingredient_id` | INTEGER | FOREIGN KEY | `ingredients.id` |
| `quantity_used` | REAL | NOT NULL | Amount deducted per order |

#### `inventory`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `item_name` | TEXT | NOT NULL | Item Name |
| `current_stock` | REAL | NOT NULL | Quantity available |
| `unit` | TEXT | NOT NULL | Kg, Gram, Ltr, Pcs |
| `low_stock_threshold`| REAL | NOT NULL | Alert threshold |
| `expiry_date` | TEXT | Nullable | Optional expiry tracking |
| `restaurant_id` | INTEGER | FOREIGN KEY | `restaurants.id` |

#### `suppliers` & `vendors`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `name` | TEXT | NOT NULL | Business name |
| `contact_person` | TEXT | Nullable | (vendors table only) |
| `contact` / `phone`| TEXT | Nullable | Contact number |
| `email` | TEXT | Nullable | (vendors table only) |
| `address` | TEXT | Nullable | Address |
| `restaurant_id` | INTEGER | FOREIGN KEY | `restaurants.id` (suppliers only) |

#### `expenses`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `description` | TEXT | NOT NULL | Expense reason |
| `amount` | REAL | NOT NULL | Amount spent |
| `date` | TEXT | NOT NULL | Timestamp |
| `category` | TEXT | NOT NULL | Expense category |
| `restaurant_id` | INTEGER | FOREIGN KEY | `restaurants.id` |

### 2.5 Miscellaneous

#### `bookings`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `table_id` | INTEGER | FOREIGN KEY | `tables.id` |
| `customer_id` | INTEGER | FOREIGN KEY | `customers.id` |
| `customer_name` | TEXT | Nullable | Display name |
| `customer_phone` | TEXT | Nullable | Contact number |
| `guest_count` | INTEGER | Nullable | Total expected guests |
| `booking_time` | TEXT | NOT NULL | Reservation timestamp |
| `status` | TEXT | NOT NULL | Pending, Confirmed, Cancelled |
| `notes` | TEXT | Nullable | Special requests |
| `restaurant_id` | INTEGER | FOREIGN KEY | `restaurants.id` |

#### `offers`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `name` | TEXT | NOT NULL | Offer title |
| `code` | TEXT | UNIQUE, NOT NULL | Promo code |
| `discount_percentage`| REAL | NOT NULL | Value in % |
| `is_active` | INTEGER | DEFAULT 1 | 1=Active, 0=Inactive |

#### `loyalty_transactions`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY | Unique ID |
| `customer_id` | INTEGER | FOREIGN KEY | `customers.id` |
| `points` | INTEGER | NOT NULL | Earned/Redeemed amount |
| `transaction_type` | TEXT | NOT NULL | Earned, Redeemed |
| `date` | TEXT | NOT NULL | Timestamp |
