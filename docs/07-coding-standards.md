# 07 — Coding Standards

Tham chiếu khi review hoặc sinh code. Đây là **rule cứng**, không phải gợi ý. Nếu thấy lý do hợp lý để vi phạm, ghi rõ trong commit message.

## Java / Spring

### Style cơ bản

- **Java 21 features**: dùng `record` cho DTO/value object, `var` khi rõ ràng, pattern matching trong `switch`.
- **Tên file = tên class.** Một public class một file.
- **Package name lowercase**, không underscore: `io.finpilot.ai.categorizer`.
- **Field nullable rõ ràng:** dùng `Optional<T>` cho return type, không cho field. Field nullable đánh dấu `@Nullable` (Spring) khi cần.

### Dependency Injection

- **Constructor injection bắt buộc.** Không dùng `@Autowired` field hoặc setter injection.
- Class có 1 constructor → Spring 6 tự inject, không cần `@Autowired`.

```java
// ĐÚNG
@Service
public class TransactionService {
    private final TransactionRepository repo;
    private final CategorizerAgent categorizer;

    public TransactionService(TransactionRepository repo, CategorizerAgent categorizer) {
        this.repo = repo;
        this.categorizer = categorizer;
    }
}

// SAI
@Service
public class TransactionService {
    @Autowired
    private TransactionRepository repo;   // KHÔNG
}
```

Hoặc dùng Lombok:
```java
@Service
@RequiredArgsConstructor
public class TransactionService {
    private final TransactionRepository repo;
    private final CategorizerAgent categorizer;
}
```

### Layer rules

| Layer | Được phép gọi | KHÔNG được |
|---|---|---|
| `web` (Controller) | `service` | repo, agent trực tiếp |
| `service` | `service` khác, `persistence`, `ai` | controller, biết về `HttpServletRequest` |
| `ai` | API LLM (qua Spring AI) | `persistence` trực tiếp (truyền data qua param) |
| `persistence` | Spring Data, `domain` | `service`, `web` |
| `domain` | Đứng một mình | bất kỳ Spring web/service |

### DTO vs Entity

- **Controller chỉ trả DTO** (record), không trả Entity. Tránh leak schema, tránh lazy-init exception.
- Map Entity ↔ DTO bằng MapStruct (hoặc manual cho case đơn giản).
- DTO đặt ở `web/dto/<feature>/`, đặt tên `<X>Request`, `<X>Response`.

### Exception

- **Custom exception ở `common/exception/`**, kế thừa `RuntimeException`.
- `@RestControllerAdvice` map sang `ProblemDetail` (RFC 7807).
- **Không** dùng exception cho control flow (vd. `EntityNotFoundException` để return null).
- `@Transactional` ở **service level**, không ở repo, không ở controller.

```java
public class TransactionNotFoundException extends RuntimeException {
    public TransactionNotFoundException(long id) {
        super("Transaction not found: " + id);
    }
}
```

### Naming

| Loại | Convention | Ví dụ |
|---|---|---|
| Class | UpperCamelCase | `TransactionService` |
| Method | lowerCamelCase, verb | `findByMonth`, `categorize` |
| Constant | UPPER_SNAKE | `MAX_BATCH_SIZE` |
| DTO | suffix Request/Response | `UploadCsvResponse` |
| Test class | `<Class>Test` (unit) hoặc `<Class>IT` (integration) | `CategorizerAgentTest` |

### File length & method length

- File ≤ 400 dòng. Vượt → tách.
- Method ≤ 50 dòng. Vượt → tách (extract).
- Class field ≤ 8. Vượt → có khả năng over-responsibility.

### Bắt buộc khi đụng tiền

- Dùng `long` (đơn vị đồng). **Không** dùng `double`/`float` cho VND.
- Convert input string `"1,200,000"` → strip `,` rồi `Long.parseLong`.
- Format output: `NumberFormat.getInstance(new Locale("vi", "VN"))`.

## Database / JPA

- `spring.jpa.hibernate.ddl-auto = validate`. Schema chỉ đổi qua Flyway.
- `@Transactional` mặc định read-only ở method query: `@Transactional(readOnly = true)`.
- **Tránh N+1.** Dùng `@EntityGraph` hoặc fetch join cho list endpoint.
- Repo method: ưu tiên derived query (`findByOccurredOnBetween`), dùng `@Query` khi phức tạp.
- Native query đặt trong `@Query(nativeQuery = true)`, không dùng JdbcTemplate trừ khi thực sự cần.
- Batch insert: `hibernate.jdbc.batch_size: 50`, `saveAll(...)` cho list lớn.

## Testing

### Phân loại

| Loại | Tag | Tốc độ | Khi chạy |
|---|---|---|---|
| Unit | (no tag) | < 100ms / test | `mvn test` |
| Integration | `@Tag("integration")` | < 5s / test | `mvn verify` |
| LLM | `@Tag("llm")` | có thể chậm + tốn token | manual hoặc CI nightly |

Maven Surefire/Failsafe filter theo `<groups>`.

### Convention

- **AAA** (Arrange-Act-Assert) blocks rõ ràng, comment hoặc blank line.
- AssertJ: `assertThat(...).isEqualTo(...)`. Không dùng JUnit `assertEquals` trừ khi đơn giản.
- Mockito: `@Mock` field + `@InjectMocks` cho service test, hoặc `Mockito.mock()` thủ công.
- Test name: `methodName_should<DoX>_when<Y>` hoặc `should<DoX>_when<Y>` (chọn 1, nhất quán).
- Fixture data ở `src/test/resources/fixtures/`.

### Integration test

- Dùng Testcontainers Postgres. Khai báo qua `@ServiceConnection` (Spring Boot 3.1+).
- `@SpringBootTest` + `@AutoConfigureMockMvc` cho controller IT.
- Mỗi test method tự cleanup bằng `@Transactional` (Spring rollback) HOẶC `@Sql` reset.

```java
@SpringBootTest
@AutoConfigureMockMvc
@Testcontainers
class TransactionControllerIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16");

    @Autowired MockMvc mvc;

    @Test
    void shouldUploadCsv_whenValidFile() throws Exception {
        var file = new MockMultipartFile("file", "vcb.csv", "text/csv",
            getClass().getResourceAsStream("/fixtures/vcb.csv"));
        mvc.perform(multipart("/api/transactions/upload").file(file))
           .andExpect(status().isOk())
           .andExpect(jsonPath("$.createdCount").value(80));
    }
}
```

## Frontend (Thymeleaf + HTMX)

- 1 layout cha `layout.html` (header, nav, footer).
- Mỗi trang `extends` layout.
- HTMX swap target rõ ràng (`hx-target="#tx-table"`), không swap toàn page.
- CSS: Tailwind CDN cho MVP. Không thêm preprocessor.

## Logging

- SLF4J: `private static final Logger log = LoggerFactory.getLogger(MyClass.class);` hoặc `@Slf4j` Lombok.
- Log level:
  - `ERROR`: lỗi không recover được, đã rollback.
  - `WARN`: edge case xử lý được nhưng đáng chú ý (parse skip dòng, fallback model).
  - `INFO`: business event (import done, chat answered).
  - `DEBUG`: chi tiết cho dev.
- **Không log secret, không log cả file CSV.** Log size, hash, count thôi.

## Git

- Branch: `main` (luôn deploy được). Feature: `feat/<short-desc>`. Fix: `fix/<short-desc>`.
- Commit message format:
  ```
  <type>(<scope>): <verb> <object>

  Optional body (≥ 72 cols wrap).
  ```
  Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `style`.
  Ví dụ: `feat(chat): add comparePeriods tool`, `fix(parser): handle BOM in vcb csv`.
- 1 PR = 1 mục đích. PR description nêu: vấn đề, giải pháp, file ảnh hưởng, cách test.

## Anti-pattern phải tránh

- ❌ `@Autowired` field injection.
- ❌ `Optional<T>` ở field hoặc parameter.
- ❌ Static method gọi service (vi phạm DI).
- ❌ Hardcode prompt template trong Java string.
- ❌ Hardcode magic number, magic string. Đưa vào `application.yml` hoặc enum.
- ❌ Method trả về null cho list. Trả `List.of()`.
- ❌ Catch `Exception` trống. Phải log hoặc rethrow.
- ❌ Lưu BigDecimal cho VND. Dùng `long` đơn vị đồng.
- ❌ Gọi LLM trong vòng lặp không có cache.
- ❌ `System.out.println` trong code thường (test debug ok, code thường không).
