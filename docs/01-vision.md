# 01 — Vision: Vấn đề & lý do tồn tại

## Vấn đề thực

Mỗi tháng nhận sao kê ngân hàng (CSV/Excel/PDF). Để biết "tháng này tiêu vào đâu nhiều nhất?" hay "ăn uống tăng bao nhiêu so với tháng trước?", phải tự mở Excel, lọc, gán nhãn, tính. Việc này lặp đi lặp lại — chính xác là thứ AI làm tốt.

## Giải pháp

FinPilot: upload sao kê → AI tự phân loại từng giao dịch → có dashboard và có thể chat tự nhiên với dữ liệu tài chính của mình.

## Vì sao project này tốt cho việc học

1. **Domain đã quen** (banking/transaction) → viết spec tốt hơn, đánh giá output AI chính xác hơn.
2. **Có lý do chính đáng** để dùng nhiều agent (parse, classify, analyze, chat) — không gượng ép.
3. **Đủ nhỏ** để hoàn thành MVP trong 2-3 weekend.
4. **Đủ phức tạp** để chạm vào: REST API, database, file upload, structured LLM output, tool calling, multi-agent orchestration.

## Đối tượng người dùng

Single user — chính tác giả. Không multi-tenant, không đăng ký, không phân quyền. Đây là quyết định **có chủ đích** để giảm scope, tập trung vào phần AI.

## Mục tiêu học tập (sau khi xong MVP)

1. **Spec-driven development** — viết spec trước khi code, dùng AI để implement đúng spec.
2. **Cấu trúc context cho AI agent** — bộ tài liệu giúp Claude Code làm việc nhất quán xuyên suốt project.
3. **Structured output từ LLM** — bắt LLM trả về JSON đúng schema (không phải parse text bằng regex).
4. **Tool calling pattern** — agent tự quyết định gọi tool nào; đây là core của agentic systems.
5. **Multi-agent orchestration** — phối hợp nhiều agent, mỗi agent một việc.
6. **Spring AI** — framework hot, đang là cách standard để dùng LLM trong Java.
7. **Cách review code do AI sinh** — không tin mù, có quy trình verify.

## Out of Scope (cố ý loại trừ)

| Thứ | Lý do loại |
|---|---|
| Multi-user, đăng ký, phân quyền | Personal app, không cần |
| Mobile app | Frontend không phải mục tiêu học |
| Real-time websocket | Không có use case |
| Microservices | Monolith dễ học hơn |
| Docker/K8s deployment | Local dev đủ cho MVP |
| Bank API integration thật | CSV upload an toàn hơn |
| Mã hoá dữ liệu nâng cao | Local DB, single user |
| Báo cáo PDF export | Dashboard HTML đủ |
| Spring Security | Không cần auth |
| LangChain4j/LangGraph | Học orchestration tay trước |

Nếu task nào lấn vào danh sách trên, hãy thảo luận trước khi làm — có thể đẩy sang Phase 4 hoặc một project sau.

## Success Criteria của MVP

- Upload được file CSV bất kỳ (≥ 2 format ngân hàng) → giao dịch lưu đúng vào DB.
- Mỗi giao dịch được AI gán category, accuracy ≥ 80% trên tập test tự kiểm.
- `GET /transactions/summary?month=2026-04` trả về breakdown đúng số liệu.
- Chat: hỏi "Tôi tiêu nhiều nhất vào gì tháng trước?" → AI trả lời đúng dựa trên data thật (verify bằng SQL).
- Analyst sinh ≥ 3 insight có nghĩa cho 1 tháng dữ liệu mẫu.
- ≥ 1 unit test + ≥ 1 integration test cho mỗi agent.
- Tổng chi phí OpenAI ≤ $5 cho toàn bộ quá trình development.
