# NGINX_REVERSE_PROXY.md

Documentation for the Nginx reverse proxy setup created in Lesson 13, Homework 2 —
Nginx on port 80 forwarding all traffic to Apache on port 8080.

## Architecture diagram

```
                    port 80                    port 8080
  Internet/Client ───────────► Nginx ───────────────────► Apache
    (curl, browser)          (reverse proxy)          (backend, PHP-capable)
                                   │
                                   └── /health ──► answered directly by Nginx
                                                    (never reaches Apache)
```

Nginx is the only service exposed to clients on the standard HTTP port (80).
Apache never listens on a public-facing port — it only accepts connections from
`127.0.0.1:8080`, which Nginx forwards to internally. This is the same
front/backend split described in the lesson: Nginx handles the public edge (TLS
termination, static assets, load balancing potential), while Apache handles
whatever it's specialized for (e.g. PHP applications) behind it.

## Setup summary

1. **Apache** installed and moved off port 80 onto port 8080
   (`/etc/apache2/ports.conf`: `Listen 8080`), since Nginx already owns port 80.
2. **Nginx** configured with an `upstream apache_backend { server 127.0.0.1:8080; }`
   block and a `server { listen 80 default_server; }` block that proxies `/` to it.
3. A dedicated `/health` location answers directly from Nginx, without touching
   Apache — useful for load balancer / monitoring health checks that shouldn't
   depend on the backend being healthy too.

## Nginx config used

```nginx
upstream apache_backend {
    server 127.0.0.1:8080;
}

server {
    listen 80 default_server;
    server_name localhost;

    location / {
        proxy_pass http://apache_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    access_log /var/log/nginx/apache_proxy.access.log;
    error_log /var/log/nginx/apache_proxy.error.log;
}
```

`listen 80 default_server` was necessary in this environment because the same
Nginx instance already serves `project1.local` and `project2.local` (Homework 1) on
port 80 — marking this block `default_server` makes it the fallback for any request
whose `Host` header doesn't match either of those (e.g. `localhost`).

## Explanation of proxy headers

| Header | Purpose |
|---|---|
| `Host` | Preserves the original domain the client requested, so the backend sees `localhost` instead of `127.0.0.1` |
| `X-Real-IP` | Passes the client's actual IP address — otherwise Apache would only see Nginx's own IP (`127.0.0.1`) |
| `X-Forwarded-For` | A chain of IPs the request passed through; useful when there are multiple proxies |
| `X-Forwarded-Proto` | Tells the backend whether the original client connection was `http` or `https` — important when Nginx terminates TLS but talks plain HTTP to the backend |

Without these headers, Apache's own logs would show every request as coming from
`127.0.0.1` (Nginx itself), making it impossible to trace real client activity from
the backend's perspective.

## Problems encountered and their solutions

### 1. Apache failed to start — `Address already in use ... :80`

**Cause:** Nginx was already installed and listening on port 80 when Apache was
installed; Apache's default config also tries to bind to port 80.

**Solution:** Edited `/etc/apache2/ports.conf`, changed `Listen 80` to
`Listen 8080`, then `sudo systemctl restart apache2`. Confirmed with
`sudo systemctl status apache2` → `active (running)`.

### 2. `AH00558: Could not reliably determine the server's fully qualified domain name`

**Cause:** Apache had no explicit `ServerName` directive, so it fell back to a
best-guess hostname resolution and warned about it on every start/reload.

**Solution:**

```bash
echo "ServerName localhost" | sudo tee /etc/apache2/conf-available/servername.conf
sudo a2enconf servername
sudo systemctl reload apache2
```

### 3. VM clock was ~18 days behind, breaking `apt update`

**Cause:** The VM's system clock had drifted significantly behind real time,
causing APT to reject repository release files as "not valid yet." `timedatectl`
showed `System clock synchronized: no` even with the NTP service reported as
active — NTP sync itself wasn't succeeding in this environment.

**Solution:** Manually set the correct date/time as a workaround
(`sudo date -s "..."`) after disabling NTP sync
(`sudo timedatectl set-ntp false`), which let `apt update`/`apt install` proceed
normally.

### 4. `dpkg` interrupted / broken kernel package dependency

**Cause:** An earlier interrupted `apt install` (from before the clock fix) left
`dpkg` in an inconsistent state, with `linux-main-modules-zfs` unable to configure
because its matching `linux-image` package wasn't installed.

**Solution:** `sudo dpkg --configure -a` followed by `sudo apt --fix-broken install`,
which pulled in the missing kernel image package and resolved the dependency chain
before `nginx`/`apache2` could install cleanly.

## How to monitor performance / traffic

```bash
# Live tail of proxy traffic
sudo tail -f /var/log/nginx/apache_proxy.access.log

# Generate test traffic
for i in {1..10}
do
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost
done

# Watch for backend errors specifically
sudo tail -f /var/log/nginx/apache_proxy.error.log
```

A `502 Bad Gateway` from Nginx at this point would mean Apache stopped responding
on port 8080 — the first things to check would be `sudo systemctl status apache2`
and `sudo ss -tlnp | grep 8080`.

## Verification performed

```bash
curl -v http://localhost         # → Apache's default page (10,672 bytes), via Nginx on port 80
curl -v http://localhost/health  # → 200 "healthy" answered directly by Nginx
```

10 sequential requests to `http://localhost` all returned `200`, and
`apache_proxy.access.log` recorded each one with the correct status and identical
response size — confirming the client-facing port (80, Nginx) and the backend port
(8080, Apache) are correctly decoupled, with Nginx transparently proxying every
request between them.