# KOS Restaurant ERP & POS System

A complete enterprise-grade Restaurant ERP & POS Management System built with Flutter and SQLite.

## Features

- **POS Billing System**: High-speed billing interface with cart management.
- **Localhost Web Ordering**: Built-in Shelf server to serve local API for customer ordering.
- **Table Management**: Live table status tracking.
- **Kitchen KOT**: Real-time order updates for the kitchen.
- **Inventory Tracking**: Stock management and alerts.
- **Analytics Dashboard**: Real-time sales and metrics.

## Tech Stack

- **Frontend**: Flutter (Latest)
- **Database**: SQLite (via `sqflite`)
- **State Management**: BLoC (Setup ready)
- **Local Server**: Shelf (for Localhost Web Ordering)

## Project Structure

```text
lib/
├── core/
│   ├── database/       # Database helper and schema
│   └── ...
├── models/             # Data models
├── repositories/       # Data repositories
├── screens/            # UI Screens (Login, Dashboard, POS, etc.)
├── services/           # Background services (Local Server)
└── main.dart           # App entry point and routing
```

## How to Run

1.  **Get Dependencies**:
    ```bash
    flutter pub get
    ```

2.  **Run the App**:
    ```bash
    flutter run
    ```

    *Note: The app starts a local server on port 8080 for LAN access.*

## Default Credentials

- **Username**: `owner`
- **Password**: `owner123`
