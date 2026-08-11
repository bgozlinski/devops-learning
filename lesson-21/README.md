# Lesson 21 – Homework 1: Two-Container Application with Docker Volumes

## Architecture

```
[webapp :8080->5000] ---- hw21-net (custom bridge) ---- [db (postgres:17)]
                                                          |
                                                    hw21-pgdata (named volume)
```

| Component | Details |
|-----------|---------|
| `db` | `postgres:17`, data in named volume `hw21-pgdata`, **no host port published** – reachable only from containers on `hw21-net` |
| `webapp` | Flask + `psycopg2-binary`, custom image `hw21-webapp:1.0`, connects to the DB via Docker DNS name `db`, exposed on host port `8080` |
| `hw21-net` | custom bridge network – unlike the default bridge it provides built-in DNS, so containers resolve each other by name |
| `hw21-pgdata` | named volume mounted at `/var/lib/postgresql/data` |

Note: the database container publishes no port on purpose. The host's port 5432 is already taken by a native PostgreSQL installation (lesson 17), and the web app does not need host-level access – it talks to the database directly over the Docker network.

## Project structure

```
docker-hw21/
├── README.md
└── webapp/
    ├── Dockerfile
    ├── app.py
    └── requirements.txt
```

## Steps performed

### 1. Network and volume

```bash
docker network create hw21-net
docker volume create hw21-pgdata
```

### 2. Database container

```bash
docker run -d \
  --name db \
  --network hw21-net \
  -v hw21-pgdata:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=tajnehaslo \
  -e POSTGRES_DB=hw21 \
  postgres:17
```

Readiness verified with `docker logs db --tail 5`:

```
LOG:  database system is ready to accept connections
```

### 3. Web application image

`webapp/Dockerfile`:

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
```

`requirements.txt` is copied and installed **before** `app.py`, so a code change does not invalidate the dependency layer on rebuild (layer caching).

Build:

```bash
docker build -t hw21-webapp:1.0 webapp/
```

### 4. Web application container

```bash
docker run -d \
  --name webapp \
  --network hw21-net \
  -e DB_PASSWORD=tajnehaslo \
  -p 8080:5000 \
  hw21-webapp:1.0
```

The application reads its DB configuration from environment variables (`DB_HOST` defaults to `db`, `DB_NAME` to `hw21`, `DB_USER` to `postgres`; `DB_PASSWORD` is required).

## Endpoints

| Endpoint | Action |
|----------|--------|
| `GET /` | connection check – returns PostgreSQL version |
| `GET /add` | creates table `visits` if needed and inserts a row |
| `GET /list` | returns all rows from `visits` |

## Verification

### Database connectivity (webapp → db over Docker DNS)

```bash
$ curl http://localhost:8080/
{"db_version":"PostgreSQL 17.10 (Debian 17.10-1.pgdg13+1) ...","status":"ok"}
```

### Write and read

```bash
$ curl http://localhost:8080/add
{"inserted_id":1}
$ curl http://localhost:8080/add
{"inserted_id":2}
$ curl http://localhost:8080/list
{"count":2,"visits":[{"id":1,"ts":"2026-08-11T17:57:27.686682"},
                     {"id":2,"ts":"2026-08-11T17:57:27.719210"}]}
```

### Data persistence test

The key proof that the named volume works – the database container was **destroyed and recreated**, and the data survived:

```bash
docker rm -f db
docker run -d --name db --network hw21-net \
  -v hw21-pgdata:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=tajnehaslo -e POSTGRES_DB=hw21 \
  postgres:17

$ curl http://localhost:8080/list
{"count":2,"visits":[{"id":1,...},{"id":2,...}]}
```

Both rows are still present. The data lives in the volume `hw21-pgdata`, not in the container's writable layer, so the container lifecycle does not affect it.

## Conclusions

- A **named volume** decouples data from the container lifecycle – containers are disposable, data is not.
- A **custom bridge network** provides DNS-based service discovery (`db` as hostname), which the default bridge does not.
- Publishing no host port for the database is both a workaround for the occupied port 5432 and good practice – the DB is only reachable by containers that need it.
- Ordering Dockerfile instructions from least to most frequently changing maximizes layer-cache hits on rebuilds.

## Cleanup

```bash
docker rm -f webapp db
docker network rm hw21-net
docker volume rm hw21-pgdata      # removes the data as well
docker rmi hw21-webapp:1.0
```