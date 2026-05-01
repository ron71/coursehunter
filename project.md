# CourseHunter — Project Blueprint & End-to-End Flow

## 1. End-to-End Request & Event Flow

### A. Student Enrollment (Happy Path)

```
Client
  │
  │  POST /api/enrollments  (Bearer JWT)
  ▼
API Gateway (gateway-service :8080)
  │  Validates JWT signature against JWKS endpoint
  │  Routes to student-service
  ▼
Student Service
  │  Creates enrollment record (status=PENDING)
  │  Publishes EnrollmentCreatedEvent → Kafka topic: enrollment.created
  ▼
Payment Service  (Kafka consumer)
  │  Charges student payment method
  │  On success → publishes PaymentCompletedEvent → Kafka topic: payment.completed
  │  On failure → publishes PaymentFailedEvent   → Kafka topic: payment.failed
  ▼
Course Service  (Kafka consumer: payment.completed)
  │  Checks seat availability
  │  Reserves seat
  │  Publishes SeatAllocatedEvent → Kafka topic: seat.allocated
  ▼
Student Service  (Kafka consumer: seat.allocated)
  │  Updates enrollment status → COMPLETED
  │  Publishes EnrollmentCompletedEvent → Kafka topic: enrollment.completed
  ▼
Notification Service  (Kafka consumer: enrollment.completed)
  │  Sends confirmation email/SMS to student
  ▼
Audit Service  (Kafka consumer: all domain events)
     Records event for compliance log
```

### B. Compensating Flow (Payment Failure)

```
Payment Service → publishes PaymentFailedEvent
  ▼
Course Service listens → skips seat allocation (or releases if pre-allocated)
  ▼
Student Service listens → marks enrollment FAILED
  ▼
Notification Service → sends failure notification to student
```

### C. Course Query (CQRS Read Path)

```
Client
  │  GET /api/courses?subject=Math  (Bearer JWT)
  ▼
API Gateway → routes to course-service query endpoint
  ▼
Course Service — Query Handler
  │  Reads from denormalized read model (Elasticsearch / Postgres replica)
  └─ Returns lightweight CourseDto (no DB write-side joins)
```

### D. Grade Update (Async CQRS)

```
Instructor submits grade → POST /api/grades
  ▼
Gradebook Service — Command Handler
  │  Writes to write-model (Postgres)
  │  Publishes GradeUpdatedEvent → Kafka
  ▼
Gradebook Read Projector (Kafka consumer)
  │  Updates read model (denormalized view)
  ▼
Student checks grade → GET /api/grades/{studentId}
  └─ Served from read model (fast, no join)
```

---

## 2. Service Responsibilities & Key Classes

### gateway-service
- **GatewaySecurityConfig** — Configures JWT OAuth2 resource server, public/private route rules
- Routes all traffic; strips/forwards JWT claims to downstream services

```java
package com.campusconnect.gateway.security;

@Configuration
public class GatewaySecurityConfig {
    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/**", "/api/public/**").permitAll()
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
        return http.build();
    }
}
```

`application.yml`:
```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://auth-campusconnect.example.com/realms/campusconnect
          jwk-set-uri: https://auth-campusconnect.example.com/realms/campusconnect/protocol/openid-connect/certs
```

---

### student-service
- **EnrollmentService** — Initiates saga, updates enrollment state machine
- **EnrollmentEventPublisher** — Publishes domain events via Spring Cloud Stream / Kafka
- **CourseClient** — Circuit-broken REST call to course-service

**CourseClient (Circuit Breaker + Retry):**
```java
package com.campusconnect.student.client;

@Service
public class CourseClient {
    private final WebClient webClient;

    public CourseClient(WebClient.Builder builder) {
        this.webClient = builder.baseUrl("http://course-service").build();
    }

    @CircuitBreaker(name = "courseServiceCircuit", fallbackMethod = "fallbackGetCourse")
    @Retry(name = "courseServiceRetry")
    public Mono<CourseDto> getCourseById(String courseId) {
        return webClient.get()
            .uri("/api/courses/{id}", courseId)
            .retrieve()
            .bodyToMono(CourseDto.class);
    }

    private Mono<CourseDto> fallbackGetCourse(String courseId, Throwable t) {
        return Mono.just(new CourseDto(courseId, "Unavailable", "Course temporarily unreachable"));
    }
}
```

`application.yml`:
```yaml
resilience4j:
  circuitbreaker:
    instances:
      courseServiceCircuit:
        slidingWindowSize: 10
        failureRateThreshold: 50
        waitDurationInOpenState: 10s
  retry:
    instances:
      courseServiceRetry:
        maxAttempts: 3
        waitDuration: 2s
```

**EnrollmentEventPublisher:**
```java
package com.campusconnect.student.event;

@Service
public class EnrollmentEventPublisher {
    private final StreamBridge streamBridge;

    public EnrollmentEventPublisher(StreamBridge streamBridge) {
        this.streamBridge = streamBridge;
    }

    public void publishEnrollmentCompleted(EnrollmentCompletedEvent event) {
        streamBridge.send("enrollmentCompleted-out-0", event);
    }
}
```

---

### course-service (CQRS)
- `command/` — CourseCommandService (writes to Postgres write-model)
- `query/`   — CourseQueryService (reads from Elasticsearch / Postgres replica)
- `event/`   — Kafka listeners that update the read model projection

---

### payment-service
- Listens on `enrollment.created` Kafka topic
- Calls payment gateway (REST)
- Emits `PaymentCompletedEvent` or `PaymentFailedEvent`

---

### notification-service

```java
package com.campusconnect.notification.listener;

@Component
public class EnrollmentCompletedListener {
    @Bean
    public Consumer<Message<EnrollmentCompletedEvent>> enrollmentCompleted() {
        return message -> {
            EnrollmentCompletedEvent event = message.getPayload();
            // send email/SMS via NotificationGateway
        };
    }
}
```

Kafka binding:
```yaml
spring:
  cloud:
    stream:
      bindings:
        enrollmentCompleted-in-0:
          destination: enrollment.completed.topic
        enrollmentCompleted-out-0:
          destination: enrollment.completed.topic
      kafka:
        binder:
          brokers: kafka:9092
```

---

## 3. Kafka Topics

Each domain event has its own dedicated topic — not a single shared bus. This gives independent scaling per topic, clean service ownership, and safe replay without reprocessing unrelated events.

| Topic | Producer | Consumers |
|---|---|---|
| `enrollment.created` | student-service | payment-service, audit-service |
| `payment.completed` | payment-service | course-service, audit-service |
| `payment.failed` | payment-service | student-service, notification-service |
| `seat.allocated` | course-service | student-service |
| `enrollment.completed` | student-service | notification-service, audit-service |
| `grade.updated` | gradebook-service | gradebook-projector, audit-service |

**Why one topic per event (not a single shared topic):**
- **Independent scaling** — partitions on `enrollment.created` can be tuned separately from `grade.updated`
- **No message filtering** — consumers only subscribe to topics they need; nothing is discarded
- **Backpressure isolation** — a slow consumer on one topic doesn't block unrelated services
- **Replay safety** — individual topics can be replayed for debugging without reprocessing unrelated events
- **Clear ownership** — the producing service owns its topic contract explicitly

---

## 4. Shared Events (common-library)

```
common-library/src/main/java/com/campusconnect/common/
├── event/
│   ├── EnrollmentCreatedEvent.java
│   ├── EnrollmentCompletedEvent.java
│   ├── PaymentCompletedEvent.java
│   ├── PaymentFailedEvent.java
│   ├── SeatAllocatedEvent.java
│   └── GradeUpdatedEvent.java
├── dto/
│   ├── CourseDto.java
│   ├── StudentDto.java
│   └── EnrollmentDto.java
└── config/
    └── KafkaTopicConfig.java
```

---

## 5. Containerization — Multi-Stage Dockerfile

```dockerfile
# Build stage
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /app
COPY mvnw ./
COPY .mvn .mvn
COPY pom.xml ./
RUN ./mvnw dependency:go-offline
COPY src src
RUN ./mvnw clean package -DskipTests

# Runtime stage (distroless — no shell, minimal attack surface)
FROM gcr.io/distroless/java21-debian12
WORKDIR /app
COPY --from=builder /app/target/gateway-service-*.jar app.jar
USER nonroot:nonroot
ENTRYPOINT ["java", "-jar", "app.jar"]
```

---

## 6. Kubernetes Infrastructure

### ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gateway-config
data:
  SPRING_PROFILES_ACTIVE: "prod"
  SERVER_PORT: "8080"
```

### Deployment (API Gateway)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
        - name: api-gateway
          image: campusconnect/api-gateway:1.0.0
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: gateway-config
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
```

### Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
spec:
  type: ClusterIP
  selector:
    app: api-gateway
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
      name: http
```

### Ingress (TLS via cert-manager)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: campusconnect-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
    - hosts:
        - campusconnect.example.com
      secretName: campusconnect-tls
  rules:
    - host: campusconnect.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-gateway
                port:
                  number: 80
```

---

## 7. Full Directory Structure

```
campusconnect/
├── gateway-service/
│   ├── src/main/java/com/campusconnect/gateway/
│   │   └── security/GatewaySecurityConfig.java
│   ├── src/main/resources/application.yml
│   └── Dockerfile
├── identity-service/
│   └── src/main/java/com/campusconnect/identity/
├── student-service/
│   ├── src/main/java/com/campusconnect/student/
│   │   ├── saga/EnrollmentSagaOrchestrator.java
│   │   ├── event/EnrollmentEventPublisher.java
│   │   ├── client/CourseClient.java
│   │   └── service/EnrollmentService.java
│   └── Dockerfile
├── course-service/
│   ├── src/main/java/com/campusconnect/course/
│   │   ├── command/CourseCommandService.java
│   │   ├── query/CourseQueryService.java
│   │   └── event/CourseReadModelProjector.java
│   └── Dockerfile
├── payment-service/
│   ├── src/main/java/com/campusconnect/payment/
│   └── Dockerfile
├── notification-service/
│   ├── src/main/java/com/campusconnect/notification/
│   │   └── listener/EnrollmentCompletedListener.java
│   └── Dockerfile
├── gradebook-service/
│   ├── src/main/java/com/campusconnect/gradebook/
│   └── Dockerfile
├── audit-service/
│   └── src/main/java/com/campusconnect/audit/
├── common-library/
│   └── src/main/java/com/campusconnect/common/
│       ├── dto/
│       ├── event/
│       └── config/
└── kubernetes/
    ├── configmap.yaml
    ├── gateway-deployment.yaml
    ├── gateway-service.yaml
    └── gateway-ingress.yaml
```

---

## 8. Observability

- **Distributed tracing**: OpenTelemetry Java agent attached to each service → traces exported to Jaeger/Tempo
- **Metrics**: Micrometer → Prometheus scrape → Grafana dashboards
- **Structured logs**: JSON logging → aggregated in ELK/Loki
- **Health checks**: `/actuator/health` exposed on all services, used by Kubernetes readiness probes

---

## 9. Known Issues & Future Work

### [OPEN] Seat Allocation Failure After Payment Charged

**Scenario**: Course Service fails to allocate a seat (course full) *after* Payment Service has already charged the student.

**Current behavior**: The saga has no compensation step for this case — student is charged but receives no seat.

**Options to address (to be designed)**:
1. **Compensating transaction** — emit `SeatAllocationFailedEvent`; Payment Service listens and issues a refund. Simple but poor UX (charge + refund visible to student).
2. **Soft reserve first (recommended)** — reorder saga: Course Service *holds* a seat with a TTL before payment is attempted. Payment only runs after `SeatReservedEvent`. On payment failure, Course Service releases the hold. Eliminates refund scenario entirely.

**Impact**: Student trust, financial reconciliation, support load.

**Deferred**: Needs saga redesign in course-service (reservation table + TTL scheduler) and new Kafka topics (`seat.reserved`, `seat.unavailable`, `seat.released`, `seat.confirmed`).

---

## 10. Key Design Decisions

| Decision | Rationale |
|---|---|
| Choreography Saga (not orchestration) | Avoids a single orchestrator SPOF; each service owns its step |
| Distroless runtime image | No shell = smaller attack surface; image ~50% smaller than JRE base |
| CQRS for Course/Gradebook | Read-heavy workloads need independent scaling from writes |
| Circuit Breaker on Student→Course | Course service is on the enrollment critical path; failure must degrade gracefully |
| ClusterIP + Ingress (not LoadBalancer per service) | One Ingress controller manages TLS termination for all services |
