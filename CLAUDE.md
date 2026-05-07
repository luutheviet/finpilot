# CLAUDE.md — Hướng dẫn cho AI Agent làm việc trên FinPilot

> Đây là file context **đầu tiên** mà Claude Code / Cowork / bất kỳ AI agent nào cần đọc khi bắt đầu một session làm việc trên project này. Đọc kỹ trước khi viết code.

---

## 1. Project là gì

FinPilot — Personal Finance Assistant cá nhân, single-user. Java 21 + Spring Boot 3.3+ + Spring AI + PostgreSQL. Mục tiêu kép: dùng thật (quản lý chi tiêu) và học thật (Spring AI, structured output, tool calling, multi-agent).

Đọc `README.md` để có overview, `docs/01-vision.md` để hiểu sâu mục đích.

## 2. Quy tắc bắt buộc

### 2.1. Trước khi code

1. **Luôn đọc spec liên quan trước.** Trước khi sửa entity → đọc `docs/04-data-model.md`. Trước khi thêm endpoint → đọc `docs/05-api-spec.md`. Trước khi tạo agent → đọc `docs/06-ai-agents.md`.
2. **Tuân thủ coding standards** trong `docs/07-coding-standards.md`. Không tự sáng tạo style mới.
3. **Tuân thủ tech stack** trong `docs/03-tech-stack.md`. Không thêm dependency mới mà không có lý do rõ ràng — nếu cần thêm, hỏi user trước.

### 2.2. Khi viết code

1. **Spec-driven, không đoán.** Nếu spec mơ hồ, dừng lại và hỏi user thay vì đoán intent.
2. **Một thay đổi = một mục đích.** Đừng vừa thêm feature vừa refactor vừa đổi format.
3. **Test cùng code.** Mỗi service/agent mới phải đi kèm ít nhất 1 unit test. Mỗi endpoint mới phải có integration test với Testcontainers.
4. **Không mock LLM trong unit test agent.** Test trực tiếp logic xử lý input/output. LLM call test ở integration level và để dưới profile riêng (`@Tag("llm")`).
5. **Tiết kiệm OpenAI token.** Cache merchant→category. Dùng gpt-4o-mini cho classify, chỉ dùng gpt-4o khi thực sự cần (chat, analyst).

### 2.3. Khi review hoặc commit

1. **Diff nhỏ, đơn nghĩa.** Một commit = một việc.
2. **Format commit message:** `<type>(<scope>): <verb> <object>`. Ví dụ: `feat(parser): add VCB CSV format detection`, `fix(categorizer): cache miss when merchant has trailing space`.
3. **Đừng commit `.env`** hoặc bất kỳ key nào. Check `.gitignore`.

## 3. Cấu trúc thư mục mong đợi

```
finpilot/
├── src/main/java/io/finpilot/
│   ├── FinPilotApplication.java
│   ├── config/              # @Configuration beans (SpringAi, ObjectMapper, ...)
│   ├── domain/              # Entity + value object thuần
│   │   ├── transaction/
│   │   └── category/
│   ├── persistence/         # JpaRepository, custom query
│   ├── service/             # Business logic, orchestration
│   ├── ai/                  # Tất cả agent ở đây
│   │   ├── parser/
│   │   ├── categorizer/
│   │   ├── analyst/
│   │   └── chat/
│   ├── web/                 # @RestController + DTO + Thymeleaf controller
│   └── common/              # Exception, util, error handler
├── src/main/resources/
│   ├── application.yml
│   ├── db/migration/        # Flyway: V1__init.sql, V2__...sql
│   ├── prompts/             # Prompt templates (.st cho Spring AI)
│   ├── templates/           # Thymeleaf
│   └── static/              # CSS, JS, HTMX
├── src/test/java/...
└── docs/                    # Spec, đọc kỹ trước khi code
```

Quy ước:
- Package theo **feature** ở `ai/`, theo **layer** ở phần còn lại (đơn giản, mainstream Spring).
- Một agent = một package con dưới `ai/` chứa: `XxxAgent.java`, `XxxRequest.java`, `XxxResponse.java`, prompt template ở `resources/prompts/xxx/`.

## 4. Workflow chuẩn cho mọi task

Cứ task nào tới, AI agent (Claude Code) phải làm theo trình tự:

1. **Hiểu task.** Đọc lại spec liên quan. Hỏi user nếu thiếu thông tin.
2. **Plan ngắn.** Liệt kê file sẽ sửa/tạo, test sẽ thêm. Confirm với user nếu task lớn (≥ 3 file).
3. **Implement.** Theo coding standards.
4. **Test.** Chạy `./mvnw test` (hoặc test cụ thể) trước khi báo done.
5. **Self-review.** Đọc lại diff, kiểm xem có:
   - Hardcode key/secret không?
   - Magic number / string không?
   - N+1 query không?
   - Bỏ sót null check không?
6. **Báo cáo ngắn gọn.** File đã đổi, test pass/fail, điểm đáng chú ý.

## 5. Những điều **KHÔNG** làm

- **Không** tự thêm Spring Security / authentication. Project là single-user, local-only.
- **Không** dùng `@Autowired` field injection. Constructor injection bắt buộc (xem coding standards).
- **Không** trả về Entity từ controller. Luôn dùng DTO.
- **Không** gọi LLM trong loop mà không có cache hoặc batch.
- **Không** ghi prompt template inline trong Java code. Để ở `resources/prompts/*.st`.
- **Không** tự thêm framework agent (LangChain4j/LangGraph) ở MVP. Multi-agent orchestration **viết tay** ở service layer để hiểu rõ flow.
- **Không** tạo file `*.md` mới ở root. Tài liệu mới đặt ở `docs/`.
- **Không** sửa Flyway migration đã commit. Migration mới = file mới (V2, V3, ...).

## 6. Khi mơ hồ

Nếu user yêu cầu việc:
- Mâu thuẫn với spec → chỉ ra mâu thuẫn, hỏi user xác nhận sửa spec hay sửa cách hiểu.
- Cần sửa nhiều file (≥ 5) → liệt kê plan trước, chờ user duyệt.
- Liên quan đến chi phí OpenAI tăng → cảnh báo và đề xuất phương án rẻ hơn.
- Vượt scope MVP → đặt câu hỏi: "Cái này có nằm ngoài scope ở `docs/01-vision.md` (Out of Scope), bạn vẫn muốn làm chứ?"

## 7. Các tài liệu phụ trợ

- `docs/08-prompting-guide.md` — Hướng dẫn user prompt Claude Code để được kết quả tốt nhất.
- `docs/10-roadmap.md` — Đang ở phase nào? Task tiếp theo là gì?

Đọc xong CLAUDE.md, bước tiếp theo thường là `docs/10-roadmap.md` để xác định task hiện tại.
