# 06 — AI Agents Specification

Bốn agent. Mỗi agent là một Spring `@Component` ở package `ai/<name>/`. Mỗi agent có **một** input contract và **một** output contract rõ ràng. Service layer compose chúng.

## Nguyên tắc chung cho mọi agent

1. **Single responsibility.** Một agent một việc. Đừng nhồi.
2. **Input/Output là record** Java thuần. Không lộ chi tiết Spring AI ra ngoài.
3. **Prompt template ở `resources/prompts/<agent>/*.st`**, không inline.
4. **Có `system` prompt cố định + `user` prompt động.** System prompt định nghĩa role, ràng buộc, format.
5. **Structured output:** dùng `BeanOutputConverter` của Spring AI hoặc OpenAI JSON mode.
6. **Có `@Tag("llm")` test** riêng (không chạy trong CI mặc định, để tiết kiệm token).
7. **Log:** input size, output size, model dùng, tokens, latency.
8. **Fail-soft:** nếu LLM lỗi, agent trả về Optional.empty() hoặc fallback rõ ràng — service layer quyết định xử lý.

---

## 1. Parser Agent — `ai/parser/`

**Trách nhiệm:** nhận một file CSV thô (có thể có cột tiếng Việt, header lạ, dấu phẩy/chấm phẩy lẫn lộn) → trả về list giao dịch chuẩn hoá.

### Contract

```java
public record ParseRequest(
    String csvContent,         // toàn bộ file dạng String
    String fileName,           // để log
    String bankHint            // null hoặc "vcb", "bidv", ...
) {}

public record ParsedTransaction(
    LocalDate occurredOn,
    long amountVnd,            // âm = chi
    String descriptionRaw,
    String bankCode            // nếu detect được
) {}

public record ParseResult(
    List<ParsedTransaction> transactions,
    String detectedBankCode,
    int skippedRows,
    List<String> warnings
) {}
```

### Approach

1. Đọc 5 dòng đầu để LLM phân tích **cấu trúc** (cột nào là date, amount debit/credit, description). LLM trả về JSON mapping:
   ```json
   {
     "delimiter": ",",
     "dateColumn": "Ngày giao dịch",
     "dateFormat": "dd/MM/yyyy",
     "debitColumn": "Số tiền chi",
     "creditColumn": "Số tiền thu",
     "descriptionColumn": "Nội dung",
     "skipRows": 6
   }
   ```
2. Sau khi có mapping, **parse phần còn lại bằng Apache Commons CSV** (Java code) — không nhờ LLM parse từng dòng (đắt + chậm).
3. Dò bank: nếu file có dòng "Ngân hàng TMCP Ngoại Thương" → `vcb`. Có thể dùng regex đơn giản, không cần LLM.

### Prompt skeleton (`prompts/parser/system.st`)

```
Bạn là parser CSV cho sao kê ngân hàng Việt Nam. Nhiệm vụ duy nhất: nhìn 5 dòng đầu của file CSV và trả về JSON mô tả cấu trúc.

Quy tắc:
- Chỉ trả JSON đúng schema, không giải thích.
- Date format ưu tiên: dd/MM/yyyy, yyyy-MM-dd, dd-MM-yyyy.
- Có thể có 1 cột "Số tiền" duy nhất (âm = chi) HOẶC 2 cột debit/credit riêng. Trả về null cho cột không có.
- skipRows = số dòng header/footer cần bỏ trước khi đọc data.

Schema:
{ "delimiter", "dateColumn", "dateFormat", "amountColumn"|null,
  "debitColumn"|null, "creditColumn"|null, "descriptionColumn", "skipRows": int }
```

### Edge cases

- File trống → throw `ParseException`.
- LLM trả format sai → retry 1 lần, sau đó throw.
- Số tiền có dấu phẩy ngăn cách phần nghìn (`1,200,000`) → strip trước khi parseLong.
- Một số ngân hàng có 2 dòng cho 1 transaction → MVP chấp nhận skip, log warning.

### Test

Unit test (`ParserAgentTest`):
- Cho mock mapping → assert parse đúng N row, amount đúng dấu, date parse đúng.
- Test 3 fixture CSV: VCB, BIDV, Techcombank (lưu ở `src/test/resources/fixtures/`).

LLM test (`@Tag("llm") ParserAgentLlmIT`):
- Đưa 5 dòng đầu thật → assert mapping LLM trả ra đúng `dateColumn`, `descriptionColumn`.

---

## 2. Categorizer Agent — `ai/categorizer/`

**Trách nhiệm:** với 1 transaction (description + amount), trả về category enum.

### Contract

```java
public record CategorizeRequest(
    String descriptionRaw,
    long amountVnd,
    String merchant   // đã normalize, có thể null
) {}

public record CategorizeResult(
    String categoryCode,    // 1 trong 9 code ở docs/04
    double confidence,      // 0.0 - 1.0
    String reasoning        // ngắn, 1 câu, để debug
) {}
```

### Flow

```
1. Lookup merchant_category_cache(merchant_normalized)
   - Hit: trả về cached, không gọi LLM.
2. Miss → gọi LLM (gpt-4o-mini)
   - Prompt: ví dụ few-shot (5-7 cặp description → category).
   - JSON output: { categoryCode, confidence, reasoning }
3. Upsert cache (sample_count++, last_seen_at = now).
```

### Few-shot examples (chọn lọc, ngắn)

```
"GRAB *RIDE 1234"           → transport
"HIGHLANDS COFFEE - Q.1"    → food
"EVN HCMC TIEN DIEN"        → utilities
"VCB chuyen khoan ATM"      → transfer
"LUONG THANG 4 CONG TY ABC" → salary
"VINMART NGUYEN HUE"        → shopping
"NETFLIX SUBSCRIPTION"      → entertainment
```

### Prompt skeleton (`prompts/categorizer/system.st`)

```
Bạn là chuyên gia phân loại giao dịch ngân hàng Việt Nam. Nhận description (có thể có tiếng Anh viết tắt, mã ATM, từ khoá quảng cáo) và amount (số âm = chi). Trả về 1 trong các category code sau, không tự bịa code mới:

{food, transport, utilities, bills, shopping, entertainment, salary, transfer, others}

Quy tắc:
- Salary: thường là số dương lớn, có "LUONG", "SALARY", "PAYROLL".
- Transfer: chuyển khoản giữa các tài khoản, "CK", "CHUYEN KHOAN".
- Others: KHÔNG match category nào ở trên (đừng abuse).
- Confidence < 0.6 = không chắc, lúc đó chọn "others".
- Trả JSON đúng schema, không giải thích ngoài lề.

Schema:
{ "categoryCode": "...", "confidence": 0.0-1.0, "reasoning": "1 câu ngắn tiếng Việt" }
```

### Tối ưu chi phí

- **Batch:** gom 10-20 transaction trong 1 prompt nếu sau khi cache vẫn còn nhiều miss. Output là array.
- Token cap: nếu description > 200 ký tự, truncate phần thừa (giữ đầu thường có info).

### Test

- Unit: mock LLM → test cache hit/miss logic, upsert cache đúng.
- LLM IT: tập 30 description thực → assert ≥ 80% match expected.

---

## 3. Analyst Agent — `ai/analyst/`

**Trách nhiệm:** đọc summary số liệu của tháng (đã được service tổng hợp từ DB) → sinh 3-5 insight có nghĩa.

### Contract

```java
public record AnalyzeRequest(
    YearMonth month,
    MonthlySummary current,
    MonthlySummary previous   // có thể null nếu không có dữ liệu tháng trước
) {}

public record Insight(
    String title,
    String body,
    Severity severity,           // INFO | WARNING | ALERT
    List<String> relatedCategories
) {}

public record AnalyzeResult(List<Insight> insights) {}
```

### Quy tắc viết prompt

- **Đưa số liệu vào, không đưa raw transaction list** (tốn token, không cần thiết).
- Yêu cầu LLM **diễn giải**, không sáng tác. Cấm bịa con số mới.
- Bắt LLM đề cập **so sánh tháng trước** (delta %) khi có.
- Output JSON đúng schema → dùng `BeanOutputConverter`.

### Prompt skeleton (`prompts/analyst/system.st`)

```
Bạn là chuyên gia phân tích chi tiêu cá nhân. Bạn nhận summary tháng hiện tại và tháng trước, rồi sinh 3-5 insight ngắn gọn, hữu ích, bằng tiếng Việt.

Yêu cầu:
- KHÔNG bịa số. Chỉ dùng số liệu trong dữ liệu được cấp.
- Ưu tiên insight có ích để hành động: bất thường, tăng đột biến, category chưa kiểm soát.
- Mỗi insight: title (≤ 60 ký tự), body (1-3 câu).
- Severity:
  - ALERT: tăng > 50% so tháng trước hoặc category vượt ngân sách hợp lý.
  - WARNING: tăng 20-50% hoặc giao dịch lặp đáng ngờ.
  - INFO: ghi nhận tích cực hoặc thông tin trung tính.
- Trả về JSON array đúng schema, KHÔNG markdown, KHÔNG bullet ngoài lề.

Dữ liệu được cấp:
- summary tháng hiện tại {month, totalIncome, totalExpense, byCategory[]}
- summary tháng trước (có thể null)

Schema mỗi insight: { title, body, severity, relatedCategories: string[] }
```

### Test

- Unit: cho summary giả → assert agent gọi LLM với prompt chứa đúng số liệu.
- LLM IT: cho summary thật → assert: ≥ 3 insight, không có số nào không xuất hiện trong input.

---

## 4. Chat Agent — `ai/chat/` (tool calling)

**Trách nhiệm:** trả lời câu hỏi tự nhiên về data tài chính. Tự quyết định gọi tool nào để truy DB.

### Contract

```java
public record AskRequest(String question) {}

public record AskResult(
    String answer,
    List<ToolCallTrace> toolCalls,   // để debug + UI hiển thị (optional)
    long modelLatencyMs,
    int totalTokens
) {}
```

### Tools expose ra LLM

Mỗi tool là một function bean. Spring AI 1.0 dùng `@Tool` (hoặc `FunctionCallback`).

```java
@Tool(description = "Liệt kê giao dịch trong khoảng thời gian. Dùng khi user hỏi giao dịch cụ thể.")
public List<TransactionDto> queryTransactions(
    LocalDate startDate,
    LocalDate endDate,
    String categoryCode,    // nullable
    Long minAmount,         // nullable
    Long maxAmount          // nullable
) { ... }

@Tool(description = "Trả tổng chi/thu và breakdown theo category cho 1 tháng (yyyy-MM).")
public MonthSummaryDto getCategorySummary(YearMonth month) { ... }

@Tool(description = "So sánh chi tiêu giữa 2 tháng (yyyy-MM).")
public PeriodComparisonDto comparePeriods(YearMonth periodA, YearMonth periodB) { ... }

@Tool(description = "Top N merchant chi nhiều nhất trong 1 tháng.")
public List<MerchantSpendDto> findTopMerchants(YearMonth month, int limit) { ... }
```

Mọi tool **chỉ đọc DB**, không có side effect. AI **không** được cấp tool ghi/xoá ở MVP.

### System prompt skeleton

```
Bạn là trợ lý tài chính cá nhân của một người dùng Việt Nam. Trả lời ngắn gọn, chính xác, bằng tiếng Việt. Tiền tệ là VNĐ.

Quy tắc bắt buộc:
- KHÔNG tự bịa số liệu. Mỗi con số trong câu trả lời phải đến từ kết quả của 1 tool call ở trên.
- Khi câu hỏi cần dữ liệu, phải gọi tool tương ứng. Nếu không có tool phù hợp, trả lời thật là không có dữ liệu.
- Sau khi gọi tool xong, tổng hợp thành câu trả lời tự nhiên ngắn gọn (≤ 4 câu).
- Format số: dùng dấu chấm ngăn cách hàng nghìn (1.000.000đ).
- Nếu user hỏi mơ hồ ("tháng trước"), hiểu là tháng trước so với "hôm nay" (truyền vào prompt).

Hôm nay: {{today}} (yyyy-MM-dd).
```

### Flow nội bộ

```
1. Build ChatClient với tool registry.
2. user message → openai gpt-4o.
3. LLM có thể trả về tool_calls → Spring AI auto-execute method, gửi result lại LLM.
4. Lặp đến khi LLM trả final message (không còn tool call).
5. Trả về AskResult kèm trace để debug.
```

### Test

- Unit: test mỗi tool method độc lập (như service test bình thường).
- LLM IT: 5 câu hỏi mẫu, assert answer chứa **chính xác** số liệu mà ta tự tính bằng SQL.

---

## Cross-cutting

### Cost guardrail

`finpilot.ai.cost-cap-usd: 5.0` ở config. Có một bean `CostMeter` đếm token theo log của Spring AI; khi vượt cap → log WARN. (Không hard-block để tránh hỏng dev flow.)

### Retry & timeout

```yaml
spring.ai.openai.chat.options:
  temperature: 0.2
  request-timeout: 30s
spring.ai.retry:
  max-attempts: 3
  backoff:
    initial-interval: 1s
    multiplier: 2
```

### Prompt versioning

- Mỗi prompt template có header comment: `# version: 1, date: 2026-05-07, author: viet`.
- Khi đổi prompt làm thay đổi behavior → bump version + ghi changelog ngắn ở đầu file.

### Cấu trúc file mỗi agent

```
ai/categorizer/
├── CategorizerAgent.java          # @Component
├── CategorizeRequest.java         # record
├── CategorizeResult.java          # record
└── (test ở src/test/java/.../categorizer/)

resources/prompts/categorizer/
├── system.st
└── user.st
```
