# Lesson 20 — Docker & Microservices Architecture, Part 1


## Setup verification

Docker was already installed from the official Docker repository (version 29.5.2 — newer than the `docker.io` 29.1.3 candidate in Ubuntu's own repos). Pre-flight checks:

```bash
systemctl is-active docker        # active
groups | grep docker              # user already in docker group
docker run hello-world            # OK
```

Note on the lesson's install instructions: they are outdated for current Ubuntu — `apt-key add` is deprecated (modern method: GPG keyring in `/etc/apt/keyrings/` + signed-by in the sources entry), and the repository line is hardcoded to `jammy` (22.04). Not an issue here since Docker was already present.

---

## Homework 1 — Multi-container application (Nginx + PostgreSQL)

Pulled both official images (`docker image pull nginx`, `docker image pull postgres`), then started the containers:

```bash
docker container run -d --name my_nginx -p 8080:80 nginx
docker container run -d --name my_postgres -p 15432:5432 -e POSTGRES_PASSWORD=*** postgres
```

**Port conflict encountered (and why 15432):** the first attempt with `-p 5432:5432` failed with `failed to bind host port 0.0.0.0:5432: address already in use` — the native PostgreSQL 18 from lesson 17 listens on 5432 (and the Patroni cluster occupies 5433–5435). Diagnosed with `sudo ss -tlnp | grep :5432`. Instead of stopping the native service, the container was remapped to host port 15432. Key takeaway about port mapping: inside the container PostgreSQL still listens on its standard 5432 — only the host side of the `-p host:container` mapping changes. The failed container had been created without networking, so it required `docker container rm` before retrying.

**Modifying the Nginx start page** via one-shot `docker exec` (no interactive session needed):

```bash
docker exec my_nginx sh -c 'echo "<h1>...</h1>" > /usr/share/nginx/html/index.html'
curl -s http://localhost:8080   # returns the new HTML
```

**Logs** (`docker logs` shows stdout/stderr of the container's main process — official images deliberately log there instead of to files):

- `my_nginx`: worker processes started, access-log entries for our curl requests (`GET / 200`)
- `my_postgres`: init sequence ending with `database system is ready to accept connections` (PostgreSQL 18.4)

**Database connectivity verified** from inside the container (socket connection, no password needed):

```bash
docker exec my_postgres psql -U postgres -c "SELECT version();"
# PostgreSQL 18.4 (Debian 18.4-1.pgdg13+1) ...
```

The `-e POSTGRES_PASSWORD` variable is mandatory for the postgres image — without it the container exits immediately (the classic "container starts and stops right away" case from the lesson's troubleshooting section).

---

## Homework 1.5 — Modifying a container and `docker commit`

Steps 1–4 (run, exec, modify, verify) were already done in HW1 on `my_nginx`. The commit step:

```bash
docker commit my_nginx moj-nginx:v1
```

`docker commit` freezes the container's **writable layer** (the layer a container adds on top of the read-only image layers) as a new image layer — the modified `index.html` becomes part of the template.

Survival test — destroy the original container, start a fresh one from the new image:

```bash
docker stop my_nginx && docker rm my_nginx
docker run -d --name test-commit -p 8080:80 moj-nginx:v1
curl -s http://localhost:8080   # modified HTML still served
```

The change survived `docker rm` because it now lives in the image, not in a single container instance. This is the image-vs-container distinction in practice: previously the modification existed only in one container's writable layer and would die with it; after commit it is a template any number of containers can be stamped from. As the lesson notes, `docker commit` is a learning stepping stone — production images are always built from a Dockerfile (repeatable, reviewable, versionable).

---

## Homework 2 — Custom Docker image from a Dockerfile

Project `~/docker-www` with two files — a static page and a two-instruction Dockerfile:

```dockerfile
FROM nginx:latest
COPY index.html /usr/share/nginx/html/index.html
```

Build and run:

```bash
docker build -t moja-strona:1.0 .
docker run -d --name moja-strona -p 8080:80 moja-strona:1.0
curl -s http://localhost:8080   # custom page served
```

Observations:

- Build took **1.9s** — the `FROM nginx:latest` layer came entirely from cache (pulled in HW1); only the `COPY` layer was new. Layer caching in action.
- The trailing `.` in `docker build` is the **build context** — the directory whose files `COPY` can reference.
- Tagged `1.0` explicitly instead of relying on the default `latest` — versioning from the start.
- `moj-nginx:v1` (from commit) and `moja-strona:1.0` (from Dockerfile) ended up the **same size** (238MB / 63.1MB compressed) — the same change achieved two ways; the Dockerfile way is simply reproducible as code.

---

## Cleanup and final state

Task containers stopped and removed; images kept as artifacts for lesson 21:

```
nginx:latest, postgres:latest, moj-nginx:v1, moja-strona:1.0, hello-world:latest
```