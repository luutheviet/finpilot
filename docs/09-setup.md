# 09 — Setup hướng dẫn local

## Yêu cầu

| Phần mềm | Phiên bản tối thiểu | Cách kiểm |
|---|---|---|
| JDK | 21 | `java -version` |
| Maven | 3.9 (hoặc dùng `mvnw`) | `mvn -v` |
| Docker | 24+ với Compose v2 | `docker compose version` |
| Git | bất kỳ | `git --version` |
| VS Code | mới nhất | — |

Plugin VS Code khuyên dùng:
- Extension Pack for Java (Microsoft)
- Spring Boot Extension Pack (VMware)
- Claude Code (Anthropic) — đã có
- Docker (Microsoft)

## Bước 1 — Clone & cấu hình env

```bash
git clone <repo-url> finpilot
cd finpilot
cp .env.example .env
```

Mở `.env`, điền:

```bash
OPENAI_API_KEY=sk-proj-xxxxxxxxxxxxxxxx
DB_USER=finpilot
DB_PASSWORD=finpilot
DB_NAME=finpilot
DB_PORT=5432
SERVER_PORT=8080
```

**Đừng commit `.env`.** File đã có trong `.gitignore`.

## Bước 2 — Chạy PostgreSQL

```bash
docker compose up -d
docker compose ps    # kiểm container "postgres" status = running
docker compose logs -f postgres   # xem log nếu lỗi
```

Kiểm kết nối:

```bash
docker compose exec postgres psql -U finpilot -d finpilot -c "SELECT 1;"
```

## Bước 3 — Build & chạy app

```bash
./mvnw clean compile
./mvnw spring-boot:run
```

Lần đầu chạy: Flyway tự `V1__init.sql` → tạo schema + seed `category`.

Kiểm:

```bash
curl http://localhost:8080/actuator/health
# {"status":"UP"}

curl http://localhost:8080/api/categories
# [ ... 9 category ... ]
```

Mở browser: <http://localhost:8080> → trang Dashboard.

## Bước 4 — Chạy test

```bash
# Unit test (nhanh)
./mvnw test

# Integration test (cần Docker chạy — Testcontainers spin Postgres riêng)
./mvnw verify

# LLM test (gọi OpenAI thật, tốn token)
./mvnw test -Dgroups=llm
```

## Cấu trúc thư mục sau khi setup

```
finpilot/
├── .env                  # gitignored
├── .env.example
├── .gitignore
├── docker-compose.yml
├── pom.xml
├── README.md
├── CLAUDE.md
├── docs/...
├── src/
│   ├── main/
│   │   ├── java/io/finpilot/
│   │   └── resources/
│   │       ├── application.yml
│   │       ├── db/migration/V1__init.sql
│   │       ├── prompts/
│   │       ├── templates/
│   │       └── static/
│   └── test/
│       ├── java/...
│       └── resources/fixtures/
└── target/               # build output (gitignored)
```

## Workflow phát triển hàng ngày

```bash
# 1. Pull
git pull

# 2. Postgres up (nếu chưa)
docker compose up -d

# 3. Mở VS Code
code .

# 4. Mở Claude Code, paste prompt mở session (xem docs/08)

# 5. Chạy app trong dev mode (Spring DevTools auto-reload)
./mvnw spring-boot:run

# 6. Khi xong task
./mvnw test
git add -p
git commit -m "feat(...): ..."
```

## Reset DB (khi muốn xoá hết để test lại)

```bash
docker compose down -v   # -v xoá volume
docker compose up -d
./mvnw spring-boot:run   # Flyway sẽ run lại từ V1
```

## Troubleshooting

| Triệu chứng | Nguyên nhân thường gặp | Fix |
|---|---|---|
| `Connection refused: localhost:5432` | Docker chưa chạy | `docker compose up -d` |
| `Flyway validate failed: V1 checksum mismatch` | Bạn đã sửa V1 sau khi đã chạy | Reset DB: `docker compose down -v && up -d`, hoặc tạo V mới thay vì sửa |
| `OPENAI_API_KEY is required` | Quên set env | `export OPENAI_API_KEY=...` hoặc kiểm `.env` được load |
| `404 trên /api/categories` mới start | Server chưa start xong | `./mvnw spring-boot:run` chờ thấy "Started FinPilotApplication" |
| Test integration timeout | Docker đang download image lần đầu | Thử lại sau, hoặc `docker pull postgres:16` thủ công |
| HTMX swap không update | Sai `hx-target` selector | Mở DevTools Network, kiểm response HTML và id target |

## Cost monitoring (OpenAI)

Vào <https://platform.openai.com/usage> sau mỗi buổi dev. Cap budget alert ở $5 trong settings. Logs Spring AI in token count mỗi call → grep `tokens` trong log.

## Nâng cấp Spring Boot / Spring AI

Kiểm release notes của:
- Spring Boot: <https://github.com/spring-projects/spring-boot/wiki>
- Spring AI: <https://docs.spring.io/spring-ai/reference/>

Bump version trong `pom.xml`, chạy `./mvnw clean verify`. Đọc breaking changes trước khi update major version.
