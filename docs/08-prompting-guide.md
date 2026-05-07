# 08 — Prompting Guide cho Claude Code

> Tài liệu này dành cho **bạn** (developer) để biết cách hỏi Claude Code / Cowork sao cho hiệu quả khi làm việc trên FinPilot.

## Nguyên tắc 5 dòng

1. **Dẫn nguồn spec.** "Theo `docs/06-ai-agents.md` mục 2..." thay vì "làm cho tao categorizer".
2. **Một task một prompt.** Vừa thêm endpoint vừa refactor → tách 2 lần.
3. **Bắt confirm trước khi code task to** ("plan trước, đợi tôi duyệt").
4. **Yêu cầu test cùng code** ("kèm 1 unit + 1 integration test").
5. **Review diff cuối cùng**, đừng accept mù.

---

## Khi mở session mới (mỗi ngày làm việc)

Mở Claude Code, paste prompt sau:

```
Đọc CLAUDE.md và docs/10-roadmap.md. Cho tôi biết:
1. Project đang ở phase nào (theo roadmap).
2. Task gần nhất chưa hoàn thành.
3. Có gì khác lạ trong git status không.
Sau đó dừng, đợi tôi giao task tiếp.
```

Claude Code sẽ load context, không tự tiện code.

---

## Mẫu prompt cho từng loại task

### Task A — Tạo entity / migration mới

```
Theo docs/04-data-model.md, hiện chưa có bảng `chat_message`.

Hãy:
1. Tạo migration V<n+1>__chat_message.sql (n = max migration hiện có).
2. Tạo entity io/finpilot/domain/chat/ChatMessage.java đúng spec.
3. Tạo repository interface ChatMessageRepository extends JpaRepository.
4. KHÔNG sửa V1, V2 đã commit.
5. Chạy `./mvnw test`, đảm bảo Flyway validate pass.
6. Báo lại file đã tạo.
```

### Task B — Thêm endpoint REST

```
Theo docs/05-api-spec.md mục 1, endpoint `PATCH /api/transactions/{id}/category` chưa implement.

Yêu cầu:
- Controller TransactionController nhận body { categoryCode }.
- Validate categoryCode tồn tại trong bảng category, nếu không trả 400.
- Service TransactionService.overrideCategory(id, code):
  - Update transaction.category_code, set category_source='USER'.
  - Upsert merchant_category_cache với user_confirmed=true.
  - Trong cùng @Transactional.
- DTO response = TransactionResponse hiện có (xem TransactionMapper).
- Test: 1 unit (service) + 1 integration (controller, Testcontainers).

Plan trước, tôi duyệt rồi mới code.
```

### Task C — Tạo agent mới

```
Theo docs/06-ai-agents.md mục 2 (Categorizer Agent), implement agent này từ đầu:

1. Tạo package io/finpilot/ai/categorizer/.
2. Records: CategorizeRequest, CategorizeResult.
3. Class CategorizerAgent (@Component) dùng Spring AI ChatClient.
4. Prompt template: src/main/resources/prompts/categorizer/system.st (theo skeleton đã có trong spec).
5. Tích hợp cache merchant_category_cache (lookup trước khi LLM call, upsert sau).
6. Unit test: mock ChatClient, mock cache repo, assert flow đúng.
7. LLM IT (@Tag("llm")) với 5 sample description, không chạy mặc định.

Đề xuất plan từng bước trước khi viết code.
```

### Task D — Refactor

```
File io/finpilot/service/ImportService.java đang dài 280 dòng, có 3 trách nhiệm: parse, categorize, save.

Refactor:
- Tách ParseStep, CategorizeStep, PersistStep (mỗi class 1 method `execute`).
- ImportService chỉ orchestrate 3 step trên.
- KHÔNG đổi public API (signature ImportService.import giữ nguyên).
- Test cũ phải pass, không cần thêm test mới.
- Diff sạch, đặt tên class rõ ràng theo coding standards.
```

### Task E — Debug

```
Lỗi:
- Khi upload file VCB, transaction được tạo nhưng amount_vnd = 0.
- Reproduce: `curl -F "file=@fixtures/vcb-202604.csv" localhost:8080/api/transactions/upload`.
- Log đính kèm:
  ... [paste log]

Hãy:
1. Phân tích nguyên nhân (đừng đoán bừa, đọc ParserAgent + import flow).
2. Đề xuất fix tối thiểu.
3. Đợi tôi duyệt rồi mới sửa.
```

### Task F — Hỏi quyết định kiến trúc

```
Tôi đang phân vân: nên cache merchant→category trong DB hay trong memory (Caffeine)?

Theo bối cảnh ở docs/02-architecture.md ADR-003 và scope MVP, hãy phân tích trade-off ngắn:
- Trade-off chính
- Khuyến nghị
- KHÔNG code gì cả, chỉ phân tích.
```

---

## Anti-pattern khi prompt

| ❌ Tránh | ✅ Thay bằng |
|---|---|
| "Tạo cho tao categorizer" | "Theo `docs/06-ai-agents.md` mục 2, implement Categorizer Agent. Tuân thủ contract, prompt template ở `prompts/categorizer/system.st`. Plan trước khi code." |
| "Sửa lỗi upload" | "Upload file fixtures/vcb-202604.csv → amount=0. Log đính kèm. Phân tích nguyên nhân trước, đợi duyệt." |
| "Refactor cho đẹp" | "ImportService 280 dòng, tách 3 step (parse/categorize/persist). Không đổi public API. Test cũ phải pass." |
| "Thêm test" | "Thêm 1 unit test cho `TransactionService.overrideCategory` covering: happy path + categoryCode invalid + transaction not found." |
| "Sửa luôn cho tôi" với task to | "Plan trước, liệt kê file sẽ đổi, đợi tôi duyệt." |

---

## Khi Claude Code đề xuất sai

1. **Đừng cãi 1 dòng.** Yêu cầu Claude **dẫn chứng từ spec**: "Phần này lệch `docs/07-coding-standards.md` mục DI, đọc lại."
2. **Đối chiếu output thật.** Nếu test pass nhưng feel sai, hỏi: "Test có cover scenario X không? Nếu chưa, viết thêm trước khi báo done."
3. **Dừng và downgrade scope.** "Quá nhiều thay đổi, làm chỉ phần A trước. Phần B để PR sau."

---

## Sanity check ngắn trước khi accept

Mỗi PR / diff Claude tạo, tự kiểm:

- [ ] Có file/feature/test theo đúng spec đã refer?
- [ ] Có vi phạm coding standards không (field injection, BigDecimal cho VND, magic string)?
- [ ] Có hardcode key/path local không?
- [ ] Test có thật sự assert behavior, hay chỉ assert `assertThat(x).isNotNull()`?
- [ ] Migration mới có là V mới, không sửa V cũ?
- [ ] Prompt template đặt ở `resources/prompts/`, không inline Java?

---

## Slash command gợi ý cho Claude Code (nếu dùng custom commands)

Tạo `.claude/commands/` (nếu Claude Code hỗ trợ) với các template:

- `/spec <agent_name>` → "Đọc `docs/06-ai-agents.md` mục agent <agent_name>, tóm tắt contract và edge case."
- `/plan <task>` → "Theo task sau, lập plan từng bước, file sẽ đổi, không code."
- `/review-diff` → "Đọc git diff hiện tại, kiểm tra theo `docs/07-coding-standards.md`."

(Tuỳ chọn, không bắt buộc cho MVP.)
