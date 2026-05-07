# 02 — Architecture

## Tổng quan

Monolith Spring Boot. Một process. Một DB. Bốn AI agent ở package `ai/` được orchestrate ở service layer.

```
                     ┌──────────────────────────────┐
   [Browser/HTMX] ──▶│  Web layer (Controllers)     │
                     │  REST + Thymeleaf + HTMX     │
                     └──────────┬───────────────────┘
                                │
                     ┌──────────▼───────────────────┐
                     │  Service layer               │
                     │  TransactionService          │
                     │  ImportService               │
                     │  ChatService                 │
                     │  AnalystService              │
                     │  - orchestrate agents        │
                     └─────┬───────────────┬────────┘
                           │               │
              ┌────────────▼───┐    ┌──────▼─────────┐
              │  AI agents     │    │  Persistence   │
              │  - Parser      │    │  Spring Data   │
              │  - Categorizer │    │  JPA + Flyway  │
              │  - Analyst     │    └──────┬─────────┘
              │  - Chat        │           │
              │   (tool call)  │    ┌──────▼─────────┐
              └────────┬───────┘    │  PostgreSQL 16 │
                       │            └────────────────┘
              ┌────────▼─────────┐
              │  OpenAI API      │
              │  via Spring AI   │
              └──────────────────┘
```

## Layer & trách nhiệm

| Layer | Trách nhiệm | KHÔNG được |
|---|---|---|
| `web` | Nhận HTTP, validate request, gọi service, trả DTO | chứa business logic, gọi repo trực tiếp |
| `service` | Business logic, orchestrate agent + repo, transaction boundary | trả Entity ra ngoài, biết về HTTP |
| `ai/*` | Một agent duy nhất, có input/output rõ ràng | gọi DB trực tiếp, biết về HTTP |
| `persistence` | JPA repository, custom query | chứa business logic |
| `domain` | Entity JPA + value object thuần | depend vào Spring web |
| `config` | `@Configuration` beans | chứa logic |

Quy tắc: **dependency chỉ chảy xuống** (web → service → ai/persistence → domain). Không chảy ngược.

## Các flow chính

### Flow 1 — Import CSV

```
POST /transactions/upload (multipart)
  └─▶ ImportController
        └─▶ ImportService.import(file)
              ├─▶ ParserAgent.parse(rawCsv)        # AI: cột nào là gì
              │     └─▶ List<RawTransaction>
              ├─▶ for each tx (batched):
              │     └─▶ CategorizerAgent.classify(tx)
              │           ├─▶ check MerchantCategoryCache
              │           ├─▶ if miss: call OpenAI gpt-4o-mini
              │           └─▶ save cache
              ├─▶ TransactionRepository.saveAll(...)
              │     # dedup theo (date + amount + description hash)
              └─▶ return ImportResult { created, skipped, errors }
```

### Flow 2 — Chat

```
POST /chat { question }
  └─▶ ChatController
        └─▶ ChatService.ask(question)
              └─▶ ChatAgent.ask(question, tools)
                    ├─▶ OpenAI gpt-4o function calling
                    ├─▶ LLM gọi tool: query_transactions(...)
                    │     └─▶ TransactionService thực thi
                    │     └─▶ trả JSON result về LLM
                    ├─▶ LLM có thể gọi tool tiếp...
                    └─▶ LLM tổng hợp câu trả lời tự nhiên
        └─▶ trả ChatResponse { answer, citations? }
```

### Flow 3 — Insights on-demand

```
GET /insights?month=2026-04
  └─▶ InsightsController
        └─▶ AnalystService.generate(month)
              ├─▶ TransactionService.summary(month)         # số liệu
              ├─▶ TransactionService.summary(prevMonth)
              └─▶ AnalystAgent.analyze(currentSummary, prevSummary)
                    └─▶ List<Insight>
```

## Quyết định kiến trúc (ADR ngắn)

### ADR-001: Monolith, không microservices
**Bối cảnh:** project học cá nhân, single user.
**Quyết định:** monolith Spring Boot duy nhất.
**Hệ quả:** dev nhanh, deploy đơn giản, dễ refactor. Không học microservices ở project này.

### ADR-002: Multi-agent orchestrate ở service layer (viết tay)
**Bối cảnh:** có thể dùng LangChain4j hoặc tự viết.
**Quyết định:** viết tay ở MVP. Mỗi agent là một bean thuần, service compose chúng.
**Hệ quả:** hiểu rõ flow, debug dễ, không lệ thuộc framework. Có thể nâng cấp sau.

### ADR-003: Cache merchant→category trong DB
**Bối cảnh:** giao dịch lặp lại nhiều (Grab, Highlands, EVN...).
**Quyết định:** bảng `merchant_category_cache` (merchant_normalized → category). Hit cache = không gọi LLM.
**Hệ quả:** giảm 70-90% token cost trong steady state.

### ADR-004: Structured output bằng JSON schema, không parse text
**Bối cảnh:** Parser và Categorizer cần data structured.
**Quyết định:** dùng `BeanOutputConverter` của Spring AI, hoặc OpenAI JSON mode + Jackson.
**Hệ quả:** không có regex parsing, output stable.

### ADR-005: Tool calling cho ChatAgent
**Bối cảnh:** chat phải dựa trên data thật, không bịa.
**Quyết định:** dùng function calling. Tools là method trong service layer được expose qua `@Tool` (Spring AI) hoặc functional interface.
**Hệ quả:** AI tự quyết định khi nào query. User trả lời được verify bằng SQL.

### ADR-006: Frontend Thymeleaf + HTMX
**Bối cảnh:** muốn có UI nhưng không lạc đề frontend.
**Quyết định:** server-side render Thymeleaf. Tương tác động (filter, chat) dùng HTMX.
**Hệ quả:** không cần build pipeline JS, không SPA, code ít. Đẹp vừa đủ.

### ADR-007: Flyway, không Hibernate auto-DDL
**Bối cảnh:** cần track schema theo thời gian.
**Quyết định:** Flyway migration `V*__*.sql`. `spring.jpa.hibernate.ddl-auto=validate`.
**Hệ quả:** schema rõ ràng, history sạch, không bao giờ auto-update production.

## Boundary với external

- **OpenAI:** chỉ qua Spring AI `ChatClient`. Không gọi HTTP raw. Có timeout + retry config ở `application.yml`.
- **Filesystem:** file upload xử lý in-memory (vài MB CSV không cần lưu disk).
- **Không có external DB / API khác.**

## Observability tối thiểu

- Log JSON (Logback + `logstash-logback-encoder`) để dễ grep.
- Mỗi agent log: input size, output size, latency, tokens (nếu Spring AI cung cấp).
- Counter Micrometer cho: số lần cache hit/miss, số lần LLM call, lỗi parsing.
- Endpoint actuator `/actuator/health`, `/actuator/info` enable. Không expose `/env`, `/configprops` ra public (dù sao cũng local).
