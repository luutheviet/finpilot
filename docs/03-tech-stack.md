# 03 — Tech Stack

## Phiên bản chốt

| Thành phần | Version | Lý do |
|---|---|---|
| Java | 21 (LTS) | Virtual threads (`Thread.ofVirtual()`) cho I/O, pattern matching, records ổn định |
| Spring Boot | 3.3.x | Tương thích Spring AI 1.0.x; baseline Jakarta EE 10 |
| Spring AI | 1.0.x | OpenAI ChatClient, structured output, tool calling, prompt templates |
| PostgreSQL | 16 | Production-grade, JSONB cho metadata linh hoạt |
| Flyway | 10.x | Migration chuẩn |
| Jackson | bundled | JSON cho REST + structured LLM output |
| Apache Commons CSV | 1.10+ | Parse CSV ổn định, header autodetect kèm tay |
| Lombok | mới nhất | Giảm boilerplate (record-only chỗ phù hợp) |
| MapStruct | 1.5+ | Map Entity ↔ DTO compile-time |
| Testcontainers | 1.19+ | Test với Postgres thật |
| JUnit | 5.10+ | bundled với Spring Boot |
| AssertJ | bundled | Assertion fluent |
| Mockito | bundled | Mock dependency |
| HTMX | 2.x (CDN) | Tương tác động không cần JS framework |
| Tailwind CSS (CDN) | 3.x | Style nhanh, không build pipeline |
| Build | Maven 3.9+ | (đã chốt theo yêu cầu) |
| Container | Docker Compose | (đã chốt) chạy Postgres local |

## Maven dependencies (pom.xml gợi ý)

```xml
<dependencies>
    <!-- Web -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-thymeleaf</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-validation</artifactId>
    </dependency>

    <!-- Persistence -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    <dependency>
        <groupId>org.flywaydb</groupId>
        <artifactId>flyway-core</artifactId>
    </dependency>
    <dependency>
        <groupId>org.flywaydb</groupId>
        <artifactId>flyway-database-postgresql</artifactId>
    </dependency>
    <dependency>
        <groupId>org.postgresql</groupId>
        <artifactId>postgresql</artifactId>
        <scope>runtime</scope>
    </dependency>

    <!-- Spring AI (OpenAI) -->
    <dependency>
        <groupId>org.springframework.ai</groupId>
        <artifactId>spring-ai-starter-model-openai</artifactId>
    </dependency>

    <!-- CSV -->
    <dependency>
        <groupId>org.apache.commons</groupId>
        <artifactId>commons-csv</artifactId>
        <version>1.11.0</version>
    </dependency>

    <!-- Lombok + MapStruct -->
    <dependency>
        <groupId>org.projectlombok</groupId>
        <artifactId>lombok</artifactId>
        <optional>true</optional>
    </dependency>
    <dependency>
        <groupId>org.mapstruct</groupId>
        <artifactId>mapstruct</artifactId>
        <version>1.5.5.Final</version>
    </dependency>

    <!-- Actuator -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>

    <!-- Test -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-test</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>postgresql</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>junit-jupiter</artifactId>
        <scope>test</scope>
    </dependency>
</dependencies>
```

Cần `<dependencyManagement>` cho Spring AI BOM và Testcontainers BOM. Xem `pom.xml` ở root.

## Lựa chọn LLM model

| Use case | Model | Lý do |
|---|---|---|
| Categorize | `gpt-4o-mini` | Rẻ (~$0.15 / 1M input tokens), đủ thông minh cho classify enum |
| Parse CSV header | `gpt-4o-mini` | Chỉ cần đọc header, đơn giản |
| Analyst (insights) | `gpt-4o` | Cần reasoning sâu, output ngắn nên tổng cost vẫn thấp |
| Chat | `gpt-4o` | Tool calling chất lượng, hiểu câu hỏi tiếng Việt tốt |

Override qua `application.yml`:
```yaml
spring.ai.openai.chat.options.model: gpt-4o-mini  # default
finpilot.ai.models.chat: gpt-4o
finpilot.ai.models.analyst: gpt-4o
```

Có thể đổi sang model rẻ hơn (vd `gpt-4o-mini`) toàn bộ trong giai đoạn dev để tiết kiệm.

## Lý do **không** dùng

| Bị loại | Lý do |
|---|---|
| Spring Security | Single user, local. Thêm = phức tạp vô ích. |
| Redis | Cache merchant→category đã có trong Postgres, không cần thêm. |
| Kafka | Không có async event flow đáng kể. |
| Docker (cho app) | Local dev chạy `mvn spring-boot:run`. Postgres chạy Docker là đủ. |
| Microservices | Đã giải thích ở ADR-001. |
| LangChain4j / LangGraph | Mục tiêu học multi-agent từ gốc, viết tay trước. |
| Gradle | Đã chọn Maven theo yêu cầu. |
| H2 | Test integration cần Postgres thật (JSONB, full-text). Testcontainers tốt hơn. |
| React/Vue | Không phải mục tiêu học. Thymeleaf + HTMX đủ đẹp cho personal dashboard. |
| OpenAPI generator | Project nhỏ, viết controller tay nhanh hơn. Dùng SpringDoc cho swagger UI nếu cần. |

## Cấu hình `application.yml` mẫu

```yaml
spring:
  application:
    name: finpilot
  datasource:
    url: jdbc:postgresql://localhost:5432/finpilot
    username: ${DB_USER:finpilot}
    password: ${DB_PASSWORD:finpilot}
  jpa:
    hibernate.ddl-auto: validate
    properties:
      hibernate.jdbc.batch_size: 50
      hibernate.order_inserts: true
  flyway:
    enabled: true
    baseline-on-migrate: true
  ai:
    openai:
      api-key: ${OPENAI_API_KEY}
      chat.options:
        model: gpt-4o-mini
        temperature: 0.2

finpilot:
  ai:
    models:
      categorizer: gpt-4o-mini
      parser: gpt-4o-mini
      analyst: gpt-4o
      chat: gpt-4o
    cost-cap-usd: 5.0   # cảnh báo log nếu vượt

logging:
  level:
    org.springframework.ai: INFO
    io.finpilot: DEBUG
```
