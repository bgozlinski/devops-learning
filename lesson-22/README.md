# Lesson 22 – Homework: "NoteApp" Microservice System (Flask + PostgreSQL + Adminer)

## Architecture

```
DEV:   [web :5000->5000]──┐
       [adminer :8080]────┼── note-app_default ── [db (postgres:15-alpine)]
                          │                          |
PROD:  [web :80->5000]────┘                    notes_pgdata (named volume)
```

| Service | Image | DEV | PROD |
|---------|-------|-----|------|
| `web` | custom (`python:3.9-slim` + Flask) | port 5000, bind mount `.:/app` | port 80, `restart: always` |
| `db` | `postgres:${POSTGRES_VERSION}` (15-alpine) | named volume, healthcheck | + `restart: always` |
| `adminer` | `adminer:latest` | port 8080 | **not started** |

## Project structure

```
note-app/
├── app.py                        # Flask API (GET/POST /notes)
├── requirements.txt              # flask==2.3.3, psycopg2-binary==2.9.9
├── Dockerfile
├── .env                          # DB credentials, ports, postgres version
├── docker-compose.yml            # base: web + db + volume + healthcheck
├── docker-compose.override.yml   # DEV: adminer, bind mount, port 5000
└── docker-compose.prod.yml       # PROD: restart policy, port 80
```

## Configuration files

### Dockerfile

```dockerfile
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
```

Dependencies are installed before the application code is copied, so code changes do not invalidate the dependency layer (layer caching).

### .env

```env
POSTGRES_DB=notes_db
POSTGRES_USER=user
POSTGRES_PASSWORD=password
POSTGRES_VERSION=15-alpine
APP_PORT=5000
ADMINER_PORT=8080
```

Compose loads this file automatically from the project directory and substitutes `${VAR}` references in the compose files. Note: in a real project `.env` with credentials belongs in `.gitignore` (or a secrets manager); it is committed here only as course material.

### docker-compose.yml (base – shared by both environments)

```yaml
services:
  web:
    build: .
    environment:
      DB_HOST: db
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:${POSTGRES_VERSION}
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - notes_pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 3s
      timeout: 3s
      retries: 10

volumes:
  notes_pgdata:
```

No ports are published for `web` here – the port mapping is an environment-specific concern (5000 in dev, 80 in prod) and lives in the per-environment files.

### docker-compose.override.yml (DEV)

```yaml
services:
  web:
    ports:
      - "${APP_PORT}:5000"
    volumes:
      - .:/app

  adminer:
    image: adminer:latest
    ports:
      - "${ADMINER_PORT}:8080"
    depends_on:
      - db
```

This file is merged **automatically** on a plain `docker compose up`. The bind mount `.:/app` makes host-side code edits visible inside the container immediately.

### docker-compose.prod.yml (PROD)

```yaml
services:
  web:
    restart: always
    ports:
      - "80:5000"

  db:
    restart: always
```

Used explicitly: `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d`. The override file is skipped, so Adminer and the bind mount never reach production.

## Problems encountered

### Startup race condition (`relation "notes" does not exist`)

On the first `docker compose up -d`, both `POST` and `GET /notes` returned **500 Internal Server Error**. `docker compose logs web` showed the root cause:

```
Czekam na baze danych... connection to server at "db" (172.18.0.2), port 5432 failed: Connection refused
...
psycopg2.errors.UndefinedTable: relation "notes" does not exist
```

`init_db()` ran while PostgreSQL was still initializing – plain `depends_on` only orders container **startup**, it does not wait for the service inside to be **ready**. The table was never created, and every request failed afterwards.

**Fix:** a `pg_isready` healthcheck on the `db` service plus `depends_on: db: condition: service_healthy` on `web` (see base compose file above). Verified on a completely clean environment:

```bash
docker compose down -v      # remove containers AND the volume
docker compose up -d        # db reaches Healthy (7.6s), only then web starts
curl http://localhost:5000/notes
[]                          # table created correctly on first boot
```

### `docker compose restart` returns before the app is up

Right after `docker compose restart web`, curl returned `Connection reset by peer` – the restart was still in progress. A short wait resolves it; not a bug, just async behavior of the CLI worth knowing.

## Verification

### DEV (`docker compose up -d`)

```bash
$ curl -X POST http://localhost:5000/notes \
    -H "Content-Type: application/json" \
    -d '{"content": "Moja pierwsza notatka"}'
{"note":"Moja pierwsza notatka","status":"success"}

$ curl http://localhost:5000/notes
[[1,"Moja pierwsza notatka"]]

$ curl -sI http://localhost:8080 | head -1
HTTP/1.1 200 OK                     # Adminer up
```

`docker compose ps` confirmed: `web` on 5000, `adminer` on 8080, `db` with no host port (internal only).

### PROD (`docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d`)

Switched with a plain `docker compose down` (no `-v`) so the volume survived.

```bash
$ curl http://localhost/notes
[[1,"Moja pierwsza notatka"]]       # port 80 + data survived DEV→PROD

$ curl -sI http://localhost:8080 | head -1
                                    # connection refused – no Adminer

$ docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' note-app-web-1 note-app-db-1
always
always
```

Only two containers were running; `db` reported `(healthy)` in `docker compose ps`.

## Conclusions

- **Compose file layering** (`base` + `override` + `prod`) keeps one source of truth for shared config and isolates environment differences; the auto-loaded `override` makes dev the frictionless default while prod is an explicit, deliberate command.
- `depends_on` alone is **not** a readiness guarantee – for databases, a healthcheck with `condition: service_healthy` is the correct pattern.
- A named volume declared in the compose file survives `docker compose down` and even an environment switch; `down -v` is the explicit opt-in to destroy data.
- Docker 29.x ships Compose as the `docker compose` v2 plugin – the standalone `docker-compose` binary from older tutorials may not exist.

## Cleanup

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml down -v
docker rmi note-app-web adminer:latest postgres:15-alpine
```