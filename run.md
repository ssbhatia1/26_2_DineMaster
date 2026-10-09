# DineMaster — Execution & Run Guide

This document defines the exact execution paths, environment commands, and options for running the **Spring Boot Backend** and the **Flutter Frontend**.

---

## 🧭 Project Execution Path Map

| Component | Relative Path | Default Port | Description |
| :--- | :--- | :--- | :--- |
| **Spring Boot Backend** | `backend/` | `8081` | Central REST API, JWT auth, database persistence, payment & media services |
| **Flutter Frontend** | `frontend/` | Desktop Window / Web | Cross-platform client (POS, Table management, KDS, Waiter ordering) |
| **Embedded Shelf Server** | Initialized by Frontend | `8080` | Local network QR menu & WebSocket ordering server |
| **PostgreSQL Database** | Host system | `5432` | Relational database (`dinemaster`) for backend `dev` profile |

---

## 🔒 0. Activating the Isolated Project Environment First

Before executing backend or frontend commands, activate the project-contained environment (`.venv`) in your terminal session. This automatically configures the project's isolated JDK 21 and Flutter SDK:

- **Windows PowerShell:**
  ```powershell
  .\Activate.ps1
  ```
- **Windows Command Prompt (CMD):**
  ```cmd
  activate.bat
  ```
- **Linux / macOS (Bash):**
  ```bash
  source ./activate.sh
  ```

> *Tip:* Run `check-env` in PowerShell or Bash to display the active toolchain paths. Run `deactivate` when finished.

---

## ☕ 1. Spring Boot Backend Execution

### Working Directory
```bash
cd backend
```
*Full Path:* `C:\Users\ssbha\Desktop\CI_Projects\26_2_DineMaster\backend`

---

### Step A: Configure Environment
Copy the example environment file if you haven't already:

- **Windows (Command Prompt / CMD):**
  ```cmd
  copy .env.example .env
  ```
- **Windows (PowerShell) / Linux / macOS (Bash):**
  ```bash
  cp .env.example .env
  ```
*(Note: If `.env` already exists in `backend/`, you can skip this step.)*
Key configuration properties (`backend/.env`):
- `SERVER_PORT=8081`
- `DB_HOST=localhost`, `DB_PORT=5432`, `DB_NAME=dinemaster`
- `DB_USER=postgres`, `DB_PASSWORD=postgres`
- `JWT_SECRET=your_jwt_secret_key`

---

### Step B: Execution Commands

#### Option 1: Run with PostgreSQL (`dev` profile)
Connects to local PostgreSQL on port `5432` (database `dinemaster`):

- **Windows (PowerShell / Command Prompt):**
  ```powershell
  cd backend
  .\mvnw.cmd spring-boot:run -Dspring-boot.run.profiles=dev
  ```

- **Linux / macOS:**
  ```bash
  cd backend
  ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev
  ```

#### Option 2: Run in Standalone / Zero-Setup Mode (`test` profile)
Uses embedded H2 in-memory database — no local PostgreSQL server required:

- **Windows (PowerShell / Command Prompt):**
  ```powershell
  cd backend
  .\mvnw.cmd spring-boot:run -Dspring-boot.run.profiles=test
  ```

- **Linux / macOS:**
  ```bash
  cd backend
  ./mvnw spring-boot:run -Dspring-boot.run.profiles=test
  ```

#### Option 3: Run the Compiled Executable JAR
To run the production build without Maven:

1. **Package the application:**
   ```powershell
   cd backend
   .\mvnw.cmd clean package -DskipTests
   ```
2. **Execute the JAR (located in `backend/target/`):**
   ```bash
   java -jar target/dinemaster-backend-1.0.0.jar
   ```

---

### Step C: Run Backend Automated Tests
Executes the Spring Boot test suite against H2 test database:
```powershell
cd backend
.\mvnw.cmd test
```

---

### Step D: Verify Backend Status
Once started, test endpoints from terminal or browser:
```bash
# 1. Health check
curl http://localhost:8081/api/health

# 2. Public payment configuration check
curl http://localhost:8081/api/payments/config
```

---

## 📱 2. Flutter Frontend Execution

### Working Directory
```bash
cd frontend
```
*Full Path:* `C:\Users\ssbha\Desktop\CI_Projects\26_2_DineMaster\frontend`

---

### Step A: Configure Environment
Copy the example environment file if you haven't already:

- **Windows (Command Prompt / CMD):**
  ```cmd
  copy .env.example .env
  ```
- **Windows (PowerShell) / Linux / macOS (Bash):**
  ```bash
  cp .env.example .env
  ```
*(Note: If `.env` already exists in `frontend/`, you can skip this step.)*
Key configuration properties (`frontend/.env`):
- `API_BASE_URL=http://localhost:8081/api`
- `LOCAL_SERVER_PORT=8080`
- `APP_MODE=local`

---

### Step B: Install Dependencies
```bash
cd frontend
flutter pub get
```

---

### Step C: Execution Commands by Platform

#### Windows Desktop (Default)
```powershell
cd frontend
flutter run -d windows
```

#### Web (Google Chrome)
```bash
cd frontend
flutter run -d chrome
```

#### macOS Desktop
```bash
cd frontend
flutter run -d macos
```

#### Linux Desktop
```bash
cd frontend
flutter run -d linux
```

#### Android Device / Emulator
```bash
cd frontend
flutter run -d android
```

> **Note on Port 8080:** When the frontend starts, it automatically boots an embedded local Shelf HTTP and WebSocket server on `http://localhost:8080` (or local Wi-Fi IP) for instant mobile QR menu ordering.

---

### Step D: Run Frontend Analysis & Tests
```bash
# Static analysis
cd frontend
dart analyze --fatal-warnings

# Run all 41 unit and widget tests
flutter test
```

---

### Step E: Production Builds
```bash
# Windows Desktop Installer (.exe) & Release
flutter build windows --release

# Android Release APK
flutter build apk --release

# Web Production Bundle
flutter build web --release
```

---

## ⚡ 3. Running Both Frontend & Backend Concurrently

### Terminal 1: Backend
```powershell
cd C:\Users\ssbha\Desktop\CI_Projects\26_2_DineMaster\backend
.\mvnw.cmd spring-boot:run -Dspring-boot.run.profiles=dev
```

### Terminal 2: Frontend
```powershell
cd C:\Users\ssbha\Desktop\CI_Projects\26_2_DineMaster\frontend
flutter run -d windows
```

---

## 🔑 4. Default Credentials & Ports

| Service | Host / Port | Default Credentials |
| :--- | :--- | :--- |
| **Frontend Application** | Native Desktop Window / Chrome | **User:** `owner` \| **Password:** `owner123` |
| **Spring Boot Backend** | `http://localhost:8081` | Accepts JWT / REST endpoints |
| **Embedded Shelf Server** | `http://localhost:8080` | Local Wi-Fi QR customer ordering |
| **PostgreSQL Database** | `localhost:5432` | **DB:** `dinemaster` \| **User:** `postgres` |
