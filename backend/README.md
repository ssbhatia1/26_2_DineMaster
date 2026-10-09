# DineMaster — Spring Boot Backend

Enterprise REST API & Database Service for DineMaster Restaurant ERP & POS Management System.

---

## 🛠️ Tech Stack & Requirements

- **Java**: 21 LTS
- **Framework**: Spring Boot 3.3.4
- **ORM / Persistence**: Spring Data JPA & Hibernate
- **Database**: PostgreSQL (Production & Local) / H2 In-Memory (Automated Testing & Fallback)
- **Security**: Spring Security 6 with stateless JWT Bearer Tokens
- **Cloud Integrations**: Cloudinary SDK (Image & Media Uploads)
- **Payment Processing**: Decoupled Payment Gateway Service (Client Key ID Public, Secret Keys Kept Strictly on Backend)
- **Build Tool**: Apache Maven (with bundled `mvnw` wrapper)

---

## 📁 Project Structure

```
backend/
├── pom.xml                               # Maven project dependencies & build plugins
├── mvnw / mvnw.cmd                       # Maven wrapper executables
├── .env.example                          # Environment variable template
├── src/
│   ├── main/
│   │   ├── java/com/dinemaster/
│   │   │   ├── DineMasterApplication.java# Application entry point
│   │   │   ├── config/                   # Security, CORS, Cloudinary, Payment configuration
│   │   │   ├── controller/               # REST API endpoints (Auth, Tables, Menu, Orders, Payments, Media)
│   │   │   ├── dto/                      # Data Transfer Objects (Requests, Responses)
│   │   │   ├── entity/                   # JPA Entities (Restaurant, User, Table, Product, Order, etc.)
│   │   │   ├── repository/               # Spring Data JPA Repository interfaces
│   │   │   ├── security/                 # JWT Provider & Auth Filters
│   │   │   └── service/                  # Business logic (Auth, Table, Product, Order, Payment, Storage)
│   │   └── resources/
│   │       ├── application.yml           # Base application configuration
│   │       ├── application-dev.yml       # Development profile (PostgreSQL)
│   │       └── application-prod.yml      # Production profile
│   └── test/                             # Automated unit & integration tests
```

---

## ⚙️ Environment Configuration

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Configure your environment credentials in `.env`:
   ```env
   # Server Port
   SERVER_PORT=8081

   # PostgreSQL Database
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=dinemaster
   DB_USERNAME=postgres
   DB_PASSWORD=your_postgres_password

   # JWT Security
   JWT_SECRET=your_base64_256_bit_jwt_secret_key
   JWT_EXPIRATION_MS=86400000

   # Cloudinary Media Integration (Optional for local dev)
   CLOUDINARY_CLOUD_NAME=your_cloud_name
   CLOUDINARY_API_KEY=your_api_key
   CLOUDINARY_API_SECRET=your_api_secret

   # Payment Gateway Integration
   PAYMENT_GATEWAY_PROVIDER=razorpay
   PAYMENT_GATEWAY_KEY_ID=your_key_id
   PAYMENT_GATEWAY_KEY_SECRET=your_secret_key
   PAYMENT_GATEWAY_WEBHOOK_SECRET=your_webhook_secret
   ```

---

## 🚀 Running the Backend

### Prerequisites
- Java 21 JDK installed (`java -version`)
- PostgreSQL installed and running (default database `dinemaster`)

### Run with Maven Wrapper
```bash
# On Windows PowerShell / Command Prompt:
.\mvnw.cmd spring-boot:run

# On Linux / macOS:
./mvnw spring-boot:run
```

### Build Executable JAR
```bash
# Windows:
.\mvnw.cmd clean package

# Linux / macOS:
./mvnw clean package

# Run packaged JAR:
java -jar target/dinemaster-backend-1.0.0.jar
```

---

## 🧪 Testing

Run all automated unit and integration tests:
```bash
.\mvnw.cmd test
```

---

## 📡 Key REST API Endpoints

| Method | Endpoint | Description | Access |
|--------|----------|-------------|--------|
| `GET` | `/api/health` | Health and liveness status | Public |
| `POST` | `/api/auth/login` | Authenticate and get JWT token | Public |
| `GET` | `/api/tables` | Fetch all restaurant tables | Public / Authenticated |
| `POST` | `/api/tables` | Create new table | Authenticated |
| `PATCH` | `/api/tables/{id}/status` | Update real-time table status | Authenticated |
| `GET` | `/api/products` | Retrieve menu catalog | Public |
| `POST` | `/api/orders` | Place customer order | Public / Authenticated |
| `GET` | `/api/payments/config` | Get public payment provider config | Public |
| `POST` | `/api/payments/create-order` | Create gateway payment order | Authenticated |
| `POST` | `/api/payments/verify` | Verify payment signature securely | Authenticated |
| `POST` | `/api/media/upload` | Upload image to Cloudinary | Authenticated |
