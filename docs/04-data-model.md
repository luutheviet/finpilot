# 04 — Data Model

## Tổng quan các bảng

| Bảng | Mục đích |
|---|---|
| `transaction` | Giao dịch đã chuẩn hoá. Bảng chính. |
| `category` | Danh mục (lookup, không bao giờ xoá). |
| `merchant_category_cache` | Cache merchant_normalized → category để giảm LLM call. |
| `import_batch` | Mỗi lần upload file = 1 batch, để rollback / theo dõi. |
| `chat_message` | Lưu lịch sử chat (tuỳ chọn ở Phase 3). |

## Schema chi tiết

### `category`
```sql
CREATE TABLE category (
    code        VARCHAR(32) PRIMARY KEY,    -- food, transport, ...
    label_vi    VARCHAR(64) NOT NULL,
    label_en    VARCHAR(64) NOT NULL,
    color_hex   CHAR(7)     NOT NULL,
    sort_order  INT         NOT NULL DEFAULT 0,
    is_income   BOOLEAN     NOT NULL DEFAULT FALSE
);
```

Seed data ở migration `V1__init.sql`:
```
food         | Ăn uống         | Food            | #ef4444 | 10 | false
transport    | Di chuyển       | Transport       | #3b82f6 | 20 | false
utilities    | Tiện ích        | Utilities       | #10b981 | 30 | false
bills        | Hoá đơn         | Bills           | #f59e0b | 40 | false
shopping     | Mua sắm         | Shopping        | #ec4899 | 50 | false
entertainment| Giải trí        | Entertainment   | #8b5cf6 | 60 | false
salary       | Lương           | Salary          | #22c55e | 70 | true
transfer     | Chuyển khoản    | Transfer        | #6b7280 | 80 | false
others       | Khác            | Others          | #94a3b8 | 99 | false
```

### `transaction`
```sql
CREATE TABLE transaction (
    id              BIGSERIAL PRIMARY KEY,
    occurred_on     DATE        NOT NULL,
    amount_vnd      BIGINT      NOT NULL,           -- âm = chi, dương = thu
    description_raw TEXT        NOT NULL,
    merchant        VARCHAR(255),                    -- normalize từ description
    category_code   VARCHAR(32) NOT NULL REFERENCES category(code),
    category_source VARCHAR(16) NOT NULL,            -- AI | USER | RULE
    bank_code       VARCHAR(16),                     -- vcb, bidv, tcb, ...
    import_batch_id BIGINT      REFERENCES import_batch(id),
    dedup_hash      CHAR(64)    NOT NULL,            -- sha256(date|amount|description_raw)
    metadata        JSONB,                            -- raw row, balance, ref, ...
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uk_transaction_dedup UNIQUE (dedup_hash)
);

CREATE INDEX ix_transaction_occurred_on ON transaction(occurred_on);
CREATE INDEX ix_transaction_category    ON transaction(category_code);
CREATE INDEX ix_transaction_merchant    ON transaction(merchant);
```

Quy ước:
- **Tiền VND lưu BIGINT** (đơn vị đồng, không có thập phân). Tránh BigDecimal cho VND.
- `amount_vnd < 0` = chi, `> 0` = thu. Đơn giản hơn 2 cột debit/credit.
- `category_source = 'USER'` được ưu tiên cao nhất, AI không override khi reimport.

### `merchant_category_cache`
```sql
CREATE TABLE merchant_category_cache (
    merchant_normalized VARCHAR(255) PRIMARY KEY,
    category_code       VARCHAR(32)  NOT NULL REFERENCES category(code),
    confidence          DOUBLE PRECISION,      -- từ LLM
    sample_count        INT          NOT NULL DEFAULT 1,
    user_confirmed      BOOLEAN      NOT NULL DEFAULT FALSE,
    last_seen_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);
```

Quy tắc cache:
- `merchant_normalized` = lowercase, bỏ ký tự đặc biệt, trim, gộp khoảng trắng.
- Nếu user override category trong `transaction` → upsert cache với `user_confirmed = true`. User-confirmed entry **không** bị AI ghi đè.
- Lookup: hit cache = không gọi LLM.

### `import_batch`
```sql
CREATE TABLE import_batch (
    id              BIGSERIAL PRIMARY KEY,
    file_name       VARCHAR(255) NOT NULL,
    bank_code       VARCHAR(16),
    row_count       INT         NOT NULL,
    created_count   INT         NOT NULL,
    skipped_count   INT         NOT NULL,
    error_count     INT         NOT NULL,
    status          VARCHAR(16) NOT NULL,    -- PENDING | DONE | FAILED
    error_message   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### `chat_message` (tuỳ chọn — Phase 3)
```sql
CREATE TABLE chat_message (
    id          BIGSERIAL PRIMARY KEY,
    role        VARCHAR(16) NOT NULL,         -- USER | ASSISTANT | TOOL
    content     TEXT        NOT NULL,
    tool_calls  JSONB,                          -- nếu có
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_chat_message_created_at ON chat_message(created_at);
```

## Flyway migration plan

| File | Nội dung |
|---|---|
| `V1__init.sql` | Tạo bảng `category`, `transaction`, `merchant_category_cache`, `import_batch`. Seed `category`. |
| `V2__chat_message.sql` | (Phase 3) bảng `chat_message`. |
| `V3__add_*` | Bất kỳ thay đổi sau này — **không sửa V1, V2**. |

Quy tắc Flyway:
- **Không sửa migration đã commit.** Sửa schema = file `V<n+1>__*.sql` mới.
- Tên file `V<số>__<snake_case>.sql`. Ví dụ `V3__add_transaction_note_column.sql`.
- Mỗi migration idempotent nếu được (`CREATE TABLE IF NOT EXISTS` không bắt buộc, vì Flyway chỉ chạy 1 lần).

## Entity Java mẫu

```java
// io/finpilot/domain/transaction/Transaction.java
@Entity
@Table(name = "transaction")
@Getter @Setter @NoArgsConstructor
public class Transaction {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "occurred_on", nullable = false)
    private LocalDate occurredOn;

    @Column(name = "amount_vnd", nullable = false)
    private Long amountVnd;

    @Column(name = "description_raw", nullable = false, columnDefinition = "TEXT")
    private String descriptionRaw;

    private String merchant;

    @Column(name = "category_code", nullable = false)
    private String categoryCode;

    @Enumerated(EnumType.STRING)
    @Column(name = "category_source", nullable = false, length = 16)
    private CategorySource categorySource;

    @Column(name = "bank_code", length = 16)
    private String bankCode;

    @Column(name = "import_batch_id")
    private Long importBatchId;

    @Column(name = "dedup_hash", nullable = false, length = 64)
    private String dedupHash;

    @Column(columnDefinition = "JSONB")
    @JdbcTypeCode(SqlTypes.JSON)
    private Map<String, Object> metadata;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @PrePersist
    void onCreate() { createdAt = updatedAt = OffsetDateTime.now(); }
    @PreUpdate
    void onUpdate() { updatedAt = OffsetDateTime.now(); }
}
```

## Dedup hash — công thức

```
dedup_hash = sha256(
    occurred_on (yyyy-MM-dd) + "|" +
    amount_vnd (decimal string) + "|" +
    descriptionRaw.trim().toLowerCase()
)
```

Reimport cùng file → mọi row trùng skip nhờ unique constraint trên `dedup_hash`. Service layer phải catch `DataIntegrityViolationException` → đếm vào `skipped_count`, không fail cả batch.

## Truy vấn hay dùng (gợi ý query)

```sql
-- Summary tháng
SELECT category_code, SUM(amount_vnd) AS total
FROM transaction
WHERE occurred_on BETWEEN :start AND :end
GROUP BY category_code
ORDER BY total ASC;

-- Top merchant tháng (chi)
SELECT merchant, SUM(-amount_vnd) AS spent
FROM transaction
WHERE amount_vnd < 0 AND occurred_on BETWEEN :start AND :end
GROUP BY merchant
ORDER BY spent DESC
LIMIT 10;
```

Các query phức tạp dùng `@Query` JPQL hoặc native query trong repo, **không** ghép string SQL trong service.
