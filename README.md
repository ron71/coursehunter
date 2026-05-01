# CourseHunter — Online Learning Management Platform

An enterprise-grade, cloud-native microservices platform for online education. Built with Spring Boot 3.4+ / Java 21, event-driven architecture (Kafka), advanced resilience patterns (Saga, CQRS, Circuit Breaker), and deployed on Kubernetes.

---

## Services

| Service | Responsibility |
|---|---|
| `gateway-service` | JWT validation, request routing, rate limiting |
| `identity-service` | OAuth2 token issuing (Keycloak or custom) |
| `student-service` | Student profiles, enrollment Saga orchestration |
| `course-service` | Course catalog with CQRS read/write separation |
| `payment-service` | Payment processing, compensating transactions |
| `notification-service` | Email/SMS via Kafka event listeners |
| `gradebook-service` | Async grade updates (CQRS write+read model) |
| `audit-service` | Compliance event recording |
| `common-library` | Shared DTOs, events, configs |

---

## Architecture

```
              +----------------------+
              |     API Gateway      |
              | (JWT/OAuth2 + Routing)|
              +----------+-----------+
                         |
           +-------------+---------------+
           |                             |
    +------+-------+             +-------+------+
    | Student Svc  | ----REST----| Course Svc   |
    | (Saga Orches)|             | (CQRS Model) |
    +------+-------+             +-------+------+
           |                             |
     Kafka |                             | Kafka
           v                             v
    +-------------+               +--------------+
    | Payment Svc | <---> Kafka -->| Notification |
    | (Saga Step) |               |  & Gradebook |
    +-------------+               +--------------+
```

---

## Enterprise Patterns

### 1. Saga Pattern — Enrollment Flow (Choreography-based)
1. **Student Service** publishes `EnrollmentCreatedEvent`
2. **Payment Service** listens → processes payment → publishes `PaymentCompletedEvent`
3. **Course Service** listens → reserves seat → publishes `SeatAllocatedEvent`
4. **Student Service** listens for all success signals → marks enrollment `COMPLETED`
5. On failure → compensating transactions reverse each step (refund, seat release)

### 2. CQRS — Course Catalog & Gradebook
- **Write model**: handles CRUD and business logic via command handlers
- **Read model**: denormalized views stored in Elasticsearch or Postgres read replica for fast queries
- Gradebook follows the same pattern: writes via events, reads via a dedicated query service

### 3. Circuit Breaker — Inter-service Resilience
- Student Service → Course Service calls are wrapped with **Resilience4j CircuitBreaker + Retry**
- On open circuit: fallback returns a cached/degraded response instead of propagating failure

---

## Tech Stack

| Concern | Technology |
|---|---|
| Framework | Spring Boot 3.4+, Java 21 |
| Security | Spring Security 6.x, OAuth2 Resource Server, JWT |
| Messaging | Kafka via Spring Cloud Stream |
| Resilience | Resilience4j (Circuit Breaker, Retry) |
| Observability | OpenTelemetry + Micrometer |
| Containerization | Distroless multi-stage Docker builds |
| Orchestration | Kubernetes (Deployment, Service, Ingress, ConfigMap) |

---

## Quick Start

```bash
make build      # Build all services (skip tests)
make install    # Build all services and run tests
make clean      # Wipe all build artifacts
make test       # Run tests only
make run        # Start all services with Docker Compose
make stop       # Stop all running containers
make logs       # Tail logs from all containers
```

---

## Module Layout

```
campusconnect/
├── gateway-service/
├── identity-service/
├── student-service/
├── course-service/
├── payment-service/
├── notification-service/
├── gradebook-service/
├── audit-service/
├── common-library/
└── kubernetes/
```

See [project.md](./project.md) for the full end-to-end flow, code blueprints, and infrastructure details.