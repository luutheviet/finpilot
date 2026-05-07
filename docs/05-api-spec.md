# 05 — API Specification

Base URL: `http://localhost:8080`. JSON UTF-8. Tất cả timestamp ISO-8601 timezone `+07:00`.

## Quy ước chung

- Lỗi trả về `application/problem+json` (RFC 7807):
  ```json
  { "type": "about:blank", "title": "Bad Request", "status": 400,
    "detail": "amount_vnd must not be null", "instance": "/transactions" }
  ```
- Mọi POST nhận `application/json` trừ upload (`multipart/form-data`).
- Pagination dạng `?page=0&size=20&sort=occurredOn,desc` — Spring Data style.

---

## 1. Transactions

### `POST /api/transactions/upload`
Upload file CSV sao kê.

**Request:** `multipart/form-data`
- `file`: CSV (yêu cầu < 10MB)
- `bankCode` (tuỳ chọn): `vcb` | `bidv` | `tcb` | ... — nếu null, ParserAgent tự đoán.

**Response 200:**
```json
{
  "batchId": 12,
  "fileName": "vcb-202604.csv",
  "rowCount": 87,
  "createdCount": 80,
  "skippedCount": 7,
  "errorCount": 0,
  "status": "DONE"
}
```

**Lỗi:** `400` nếu file rỗng / không phải CSV. `422` nếu ParserAgent không nhận dạng được cấu trúc.

### `GET /api/transactions`
Liệt kê có filter + pagination.

**Query params:**
- `from` (date), `to` (date)
- `category` (string, repeat được)
- `minAmount`, `maxAmount` (long, VND)
- `merchant` (substring, case-insensitive)
- `page`, `size`, `sort`

**Response 200:**
```json
{
  "content": [
    {
      "id": 1234,
      "occurredOn": "2026-04-15",
      "amountVnd": -85000,
      "descriptionRaw": "GRAB *RIDE 1234",
      "merchant": "Grab",
      "category": { "code": "transport", "labelVi": "Di chuyển" },
      "categorySource": "AI",
      "bankCode": "vcb"
    }
  ],
  "page": 0, "size": 20, "totalElements": 87, "totalPages": 5
}
```

### `PATCH /api/transactions/{id}/category`
User override category.

**Request:**
```json
{ "categoryCode": "food" }
```

**Hệ quả:**
- Cập nhật `transaction.category_code`, `category_source = 'USER'`.
- Upsert `merchant_category_cache` với `user_confirmed = true`.

**Response 200:** transaction sau update.

### `GET /api/transactions/summary`
Tổng hợp theo category cho 1 tháng.

**Query:** `month=2026-04`

**Response 200:**
```json
{
  "month": "2026-04",
  "totalIncome": 25000000,
  "totalExpense": -12450000,
  "byCategory": [
    { "categoryCode": "food",      "labelVi": "Ăn uống",   "total": -3200000, "txCount": 24 },
    { "categoryCode": "transport", "labelVi": "Di chuyển", "total": -1100000, "txCount": 18 }
  ],
  "comparedToPrev": {
    "expenseDeltaVnd": -800000,
    "expenseDeltaPct": -6.0
  }
}
```

---

## 2. Categories

### `GET /api/categories`
Trả về toàn bộ category lookup. Dùng cho dropdown UI.

**Response 200:**
```json
[
  { "code": "food", "labelVi": "Ăn uống", "labelEn": "Food", "colorHex": "#ef4444", "isIncome": false },
  ...
]
```

---

## 3. Insights

### `POST /api/insights/generate`
Bắt AnalystAgent sinh insight cho 1 tháng.

**Request:**
```json
{ "month": "2026-04" }
```

**Response 200:**
```json
{
  "month": "2026-04",
  "generatedAt": "2026-05-01T10:00:00+07:00",
  "insights": [
    {
      "title": "Chi phí ăn uống tăng đột biến",
      "body": "Tháng này bạn tiêu 3.2M cho ăn uống, tăng 28% so với tháng trước. Phần lớn ở Highlands Coffee và GrabFood.",
      "severity": "WARNING",
      "relatedCategories": ["food"]
    }
  ]
}
```

Severity: `INFO` | `WARNING` | `ALERT`.

---

## 4. Chat

### `POST /api/chat`
Hỏi tự nhiên về dữ liệu.

**Request:**
```json
{ "question": "Tháng trước tôi tiêu nhiều nhất vào gì?" }
```

**Response 200:**
```json
{
  "answer": "Tháng 4/2026 bạn chi nhiều nhất cho **ăn uống**: 3.200.000đ (chiếm 26% tổng chi). Tiếp theo là di chuyển 1.100.000đ.",
  "toolCalls": [
    {
      "name": "get_category_summary",
      "arguments": { "month": "2026-04" },
      "tookMs": 18
    }
  ],
  "modelLatencyMs": 1240,
  "totalTokens": 612
}
```

`toolCalls` để debug, có thể ẩn ở UI.

### `GET /api/chat/history`
Lấy 50 message gần nhất (Phase 3 nếu có lưu lịch sử).

---

## 5. Web UI (Thymeleaf)

| Path | Trang | Mô tả |
|---|---|---|
| `GET /` | Dashboard | Cards: tổng chi/thu, breakdown category, top merchants tháng. |
| `GET /transactions` | Transactions list | Bảng có filter (form GET), HTMX để inline edit category. |
| `GET /import` | Upload page | Form multipart, hiển thị progress + kết quả batch. |
| `GET /chat` | Chat UI | Input + lịch sử, HTMX swap khi có response. |
| `GET /insights` | Insights | Nút "Generate" → POST `/api/insights/generate` → render kết quả. |

UI lấy data từ chính các `/api/*` endpoint (controller render Thymeleaf gọi service tương ứng — không gọi REST nội bộ).

## 6. Health & ops

- `GET /actuator/health` — public.
- `GET /actuator/info` — public.
- `GET /actuator/metrics` — local only (binding `127.0.0.1`).

## Gợi ý implement

- Tách `XxxController` (REST) và `XxxViewController` (Thymeleaf) thay vì dồn 1 class.
- DTO ở package `web/dto/`, đặt tên `<Action><Entity>Request` / `<Entity>Response`. Ví dụ `UploadCsvResponse`, `TransactionResponse`.
- Bean validation: `@NotNull`, `@Pattern("^\\d{4}-\\d{2}$")` cho `month` param.
- Global exception handler: `@RestControllerAdvice` chuyển `ConstraintViolationException`, `IllegalArgumentException`, `EntityNotFoundException` thành ProblemDetail.
