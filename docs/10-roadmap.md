# 10 — Roadmap (chi tiết)

4 phase. Mỗi phase có **definition of done** rõ. Chỉ chuyển phase khi mọi checkbox xanh.

---

## Phase 0 — Setup context (1 buổi, ~3-4 giờ)

**Mục tiêu:** repo init, dev environment chạy, Postgres up, app skeleton chạy. Chưa có business logic.

### Tasks

- [ ] `git init` repo, đặt tên `finpilot`.
- [ ] Copy bộ context (`README.md`, `CLAUDE.md`, `docs/*`) vào root.
- [ ] Tạo `.gitignore`, `.env.example`, `docker-compose.yml` (theo file mẫu trong bộ context).
- [ ] Khởi tạo Spring Boot project skeleton:
  - <https://start.spring.io/> → Maven, Java 21, Spring Boot 3.3+, dependencies: Web, JPA, Validation, Flyway, PostgreSQL Driver, Thymeleaf, Lombok, Actuator, Testcontainers.
  - Hoặc dùng `pom.xml` mẫu (xem file root).
- [ ] Cấu hình `application.yml` (xem `docs/03-tech-stack.md`).
- [ ] Tạo `V1__init.sql` với schema + seed `category` (xem `docs/04-data-model.md`).
- [ ] `docker compose up -d` → Postgres up.
- [ ] `./mvnw spring-boot:run` → app start, `/actuator/health` = UP.
- [ ] `curl /api/categories` (sau khi có CategoryController/Service stub) → trả 9 category.
- [ ] Commit đầu tiên: `chore: project skeleton + context docs`.

### Definition of Done

- App start không lỗi, `/actuator/health` UP.
- Flyway chạy V1 thành công, kiểm bảng có trong DB.
- README + docs đầy đủ trong repo.

---

## Phase 1 — Foundation, no AI (weekend 1)

**Mục tiêu:** đầy đủ CRUD transaction, upload CSV với parser **cứng** (chỉ format VCB hardcode). Chưa gọi LLM.

### Tasks

- [ ] Entity `Transaction`, `Category`, `ImportBatch`, `MerchantCategoryCache` (chỉ schema, chưa dùng).
- [ ] Repository: `TransactionRepository`, `CategoryRepository`, `ImportBatchRepository`.
- [ ] Service:
  - `CategoryService.findAll()`.
  - `TransactionService.find(filter, pageable)`.
  - `TransactionService.summary(month)` — query group by category.
  - `TransactionService.overrideCategory(id, code)`.
  - `ImportService.import(file, bankHint)` — parse CSV format VCB hardcode (cột date, debit, credit, description theo format VCB cụ thể), gán category mặc định `others`.
- [ ] Controller:
  - `CategoryController GET /api/categories`.
  - `TransactionController GET /api/transactions`, `PATCH /api/transactions/{id}/category`, `GET /api/transactions/summary`.
  - `ImportController POST /api/transactions/upload`.
- [ ] DTO + Mapper (MapStruct).
- [ ] `@RestControllerAdvice` global exception handler trả ProblemDetail.
- [ ] Thymeleaf trang Dashboard cơ bản (số tổng + table 20 transaction gần nhất).
- [ ] Test:
  - Unit: `TransactionService.summary` correct cho 1 fixture.
  - Integration: `ImportController` upload fixture VCB → 80 row created.

### Definition of Done

- Upload CSV VCB thật → giao dịch lưu DB, summary trả số đúng.
- `GET /` hiển thị Dashboard với data.
- 5+ test pass.

### Lưu ý

**Chưa có AI ở phase này** — chủ ý để code Spring chuẩn trước, đỡ vướng khi add AI.

---

## Phase 2 — First AI integration (weekend 2)

**Mục tiêu:** Parser Agent đa format + Categorizer Agent + cache merchant.

### Tasks

- [ ] Thêm dependency `spring-ai-starter-model-openai`.
- [ ] Cấu hình `OPENAI_API_KEY`, `application.yml` cho Spring AI.
- [ ] Implement `ParserAgent`:
  - Đọc 5 dòng đầu → LLM trả về JSON mapping cấu trúc.
  - Apache Commons CSV parse phần còn lại theo mapping.
  - Detect bank code từ keyword.
  - Test: 3 fixture (VCB, BIDV, Techcombank) → assert parse đúng.
- [ ] Refactor `ImportService` dùng `ParserAgent` thay parser hardcode.
- [ ] Implement `CategorizerAgent`:
  - Lookup `merchant_category_cache` trước.
  - Miss → call gpt-4o-mini với few-shot prompt.
  - Upsert cache.
  - Test: unit (mock LLM), LLM IT (30 sample, ≥ 80% accuracy).
- [ ] Tích hợp `CategorizerAgent` vào `ImportService` flow (sau parse, trước save).
- [ ] UI: trang Transactions có button "Sửa category" inline (HTMX), gọi PATCH endpoint.
- [ ] Cost log: log token count mỗi LLM call.

### Definition of Done

- Upload 3 file CSV (3 ngân hàng) → mỗi file parse + categorize thành công.
- ≥ 80% accuracy trên test set 30 transaction.
- Reimport cùng file → 100% skip nhờ dedup hash.
- Override category trong UI → cache cập nhật, lần import sau hit cache (không gọi LLM).

---

## Phase 3 — Multi-agent (weekend 3)

**Mục tiêu:** Analyst Agent + Chat Agent với tool calling.

### Tasks

- [ ] Implement `AnalystAgent`:
  - Input: `MonthlySummary` current + previous.
  - Output: list `Insight`.
  - Prompt nghiêm: cấm bịa số, output đúng schema.
  - Test: LLM IT — assert mọi số trong insight đều có trong input.
- [ ] Endpoint `POST /api/insights/generate`.
- [ ] UI: trang Insights, button "Generate" → render danh sách insight có severity badge.
- [ ] Implement `ChatAgent` với tool calling:
  - Tools: `queryTransactions`, `getCategorySummary`, `comparePeriods`, `findTopMerchants`.
  - Mỗi tool là method có `@Tool` (Spring AI 1.0).
  - Test unit cho mỗi tool method.
  - Test LLM: 5 câu hỏi mẫu, assert answer chứa số chính xác.
- [ ] Endpoint `POST /api/chat`.
- [ ] UI: trang Chat, input + message list, HTMX swap.
- [ ] (Tuỳ chọn) Lưu lịch sử chat vào `chat_message`.

### Definition of Done

- Hỏi "Tháng trước tôi tiêu nhiều nhất vào gì?" → câu trả lời đúng (verify SQL).
- Hỏi "So sánh chi tiêu Q1 và Q2 năm nay" → AI gọi đúng `comparePeriods` với param đúng.
- Generate insight 1 tháng → ≥ 3 insight có nghĩa, không bịa số.
- Tổng OpenAI cost từ Phase 0 → cuối Phase 3 ≤ $5.

---

## Phase 4 — Mở rộng (tuỳ chọn)

Chọn 1-2 hướng tuỳ thời gian:

### 4A — MCP server
- Expose 4 tool ở Phase 3 dưới dạng MCP server.
- Cấu hình Claude Desktop để dùng.
- Học: MCP protocol, transport stdio/sse.

### 4B — Anomaly detection
- Rule-based + LLM hybrid: phát hiện giao dịch lạ (số tiền lạ, merchant lần đầu xuất hiện, frequency tăng).
- Endpoint `GET /api/transactions/anomalies?month=...`.

### 4C — PDF support
- Parser PDF dùng AI (Apache PDFBox extract text → ParserAgent xử lý như CSV).
- Test với 1-2 file PDF sao kê thật.

### 4D — Dashboard nâng cao
- Chart.js (CDN) cho pie/line chart breakdown.
- Filter dashboard theo khoảng thời gian linh hoạt.

### 4E — Authentication tối thiểu
- Spring Security với 1 user / password trong `.env`.
- Để chuẩn bị share lên VPS riêng.

---

## Tracking tiến độ

Khuyên dùng GitHub Issues hoặc 1 file `TODO.md` riêng để track. Mỗi task = 1 issue. PR link issue. Đóng issue khi merge.

Mỗi cuối weekend, viết 1 đoạn ngắn vào `docs/changelog.md` (tự thêm) ghi: phase đang ở, đã làm gì, học được gì, blocker.

---

## "Aha moment" cần đạt được

Sau mỗi phase, bạn nên thật sự **cảm nhận** được:

| Phase | Aha |
|---|---|
| 0 | Spec-driven khác freeform code thế nào |
| 1 | Spring Boot + JPA + Flyway flow chuẩn |
| 2 | Structured output từ LLM = JSON đúng schema, không phải parse text |
| 3 | Tool calling = AI tự quyết, không cần if/else trong code |

Nếu không đạt aha thì có thể đi quá nhanh — cân nhắc viết blog post hoặc note lại để củng cố hiểu biết.
