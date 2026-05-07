# FinPilot

> **Personal Finance Assistant** — Java/Spring Boot + Spring AI + OpenAI. Upload sao kê ngân hàng → AI tự phân loại giao dịch → dashboard + chat tự nhiên với dữ liệu tài chính của bạn.

## Tại sao có project này

- Dùng thật: tự quản lý chi tiêu hằng tháng mà không cần mở Excel.
- Học thật: nắm Spring AI, structured LLM output, tool calling, multi-agent orchestration trên domain mình quen (banking/transaction).

## Tính năng MVP

1. Upload CSV sao kê (BIDV / VCB / Techcombank...) → AI parser nhận dạng cột bất kể format.
2. AI tự gán category cho từng giao dịch (food, transport, bills, ...). Có cache theo merchant để tiết kiệm token.
3. Dashboard: tổng chi/thu, breakdown theo category, so sánh tháng.
4. Chat tự nhiên với data: "Tháng trước tôi tiêu nhiều nhất vào gì?" — AI dùng tool calling để query DB thật, không bịa.
5. Insights tự động: AI sinh 3-5 nhận xét ngắn cho 1 tháng dữ liệu.

## Tech stack tóm tắt

| Layer | Chọn |
|---|---|
| Language | Java 21 |
| Framework | Spring Boot 3.3+ |
| AI | Spring AI 1.0+, OpenAI (gpt-4o-mini cho classify, gpt-4o cho chat) |
| DB | PostgreSQL 16 (Docker Compose) |
| Migration | Flyway |
| ORM | Spring Data JPA |
| CSV | Apache Commons CSV |
| Build | Maven |
| Frontend | Thymeleaf + HTMX (đơn giản) |
| Test | JUnit 5 + Testcontainers |

Chi tiết xem `docs/03-tech-stack.md`.

## Bắt đầu nhanh (TL;DR)

```bash
# 1. Copy env
cp .env.example .env
# Sau đó mở .env và điền OPENAI_API_KEY

# 2. Chạy PostgreSQL
docker compose up -d

# 3. Build + chạy app
./mvnw spring-boot:run

# 4. Mở http://localhost:8080
```

Hướng dẫn chi tiết: `docs/09-setup.md`.

## Cấu trúc tài liệu

Đọc theo thứ tự khi mới vào:

1. `docs/01-vision.md` — Vấn đề & lý do tồn tại của project.
2. `docs/02-architecture.md` — Kiến trúc hệ thống và flow chính.
3. `docs/03-tech-stack.md` — Công nghệ chi tiết và lý do chọn.
4. `docs/04-data-model.md` — Schema DB và Flyway migration.
5. `docs/05-api-spec.md` — Tất cả REST endpoint.
6. `docs/06-ai-agents.md` — Spec 4 AI agent (Parser, Categorizer, Analyst, Chat).
7. `docs/07-coding-standards.md` — Conventions Java/Spring.
8. `docs/08-prompting-guide.md` — Cách làm việc hiệu quả với Claude Code trên project này.
9. `docs/09-setup.md` — Dev setup chi tiết.
10. `docs/10-roadmap.md` — 4 phase implementation cụ thể.

`CLAUDE.md` ở root là entry point cho AI agent — đọc đầu tiên khi bắt đầu một session làm việc với Claude Code.

## Success Criteria (MVP done)

- [ ] Upload được ≥ 2 format CSV ngân hàng khác nhau, lưu DB chính xác.
- [ ] AI gán category accuracy ≥ 80% trên tập test tự kiểm.
- [ ] `GET /transactions/summary?month=YYYY-MM` trả số liệu đúng (verify bằng SQL).
- [ ] Chat: trả lời đúng 5 câu hỏi tự kiểm dựa trên data thật.
- [ ] Analyst sinh ≥ 3 insight có nghĩa.
- [ ] ≥ 1 unit test + ≥ 1 integration test mỗi agent.
- [ ] Tổng chi phí OpenAI ≤ $5 trong toàn bộ development.

## Out of scope (cố ý)

Multi-user, auth, microservices, K8s, mobile, websocket, mã hoá nâng cao, bank API thật, PDF report. Lý do: tập trung học AI workflow, không phân tán.
