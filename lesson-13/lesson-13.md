# Lesson 13 — Web Servers (Nginx / Apache)

## Environment setup issues (resolved before homework)

Before any web server work could begin, several unrelated environment problems had
to be fixed:

1. **Clock drift** — the VM's system clock was ~18 days behind real time, which
   made `apt update` reject all repository release files as "not valid yet" (even
   though `timedatectl` reported the NTP service as active, actual sync was
   failing). Fixed by disabling NTP sync and manually setting the correct date:
   `sudo timedatectl set-ntp false` + `sudo date -s "2026-07-03 ..."`.
2. **Interrupted `dpkg` state** — an earlier install attempt (during the clock
   issue) had been interrupted, leaving a kernel package
   (`linux-main-modules-zfs`) unconfigured due to a missing dependency
   (`linux-image-7.0.0-27-generic`). Fixed with `sudo dpkg --configure -a` followed
   by `sudo apt --fix-broken install`, which pulled in the missing kernel image.

Full details of both fixes and their root causes are documented in
`NGINX_REVERSE_PROXY.md` (problems 3 and 4), since they were fully diagnosed while
working through that task.

---

## Nginx installation

**Commands:**

```bash
sudo apt update
sudo apt install -y nginx
sudo systemctl status nginx --no-pager
curl -I http://localhost
ps aux | grep nginx
```

**Output (after environment fixes):**

```text
● nginx.service - A high performance web server and a reverse proxy server
     Active: active (running) since Fri 2026-07-03 17:48:18 UTC
   Main PID: 14936 (nginx)
     CGroup: /system.slice/nginx.service
             ├─14936 "nginx: master process ..."
             ├─14939 "nginx: worker process"
             ... (6 worker processes total)

HTTP/1.1 200 OK
Server: nginx/1.28.3 (Ubuntu)
Content-Length: 615
```

**Explanation:**

The process list confirms Nginx's architecture directly from the lesson theory: one
root-owned **master process** and multiple `www-data`-owned **worker processes**
(one per CPU core by default, via `worker_processes auto;`) — the event-driven
model that lets Nginx handle many concurrent connections efficiently, unlike
Apache's process/thread-per-request model.

---

## Homework 1 — Nginx with two virtual hosts

### Goal

Serve two independent sites (`project1.local`, `project2.local`) from the same
Nginx instance on port 80, each with its own document root and log files.

### Steps and verification

**Commands:**

```bash
sudo mkdir -p /var/www/project1 /var/www/project2
echo "<h1>Project 1</h1>" | sudo tee /var/www/project1/index.html
echo "<h1>Project 2</h1>" | sudo tee /var/www/project2/index.html

# sites-available/project1.conf and project2.conf created (see NGINX_VHOSTS.md)

sudo ln -s /etc/nginx/sites-available/project1.conf /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/project2.conf /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

sudo bash -c 'echo "127.0.0.1 project1.local" >> /etc/hosts'
sudo bash -c 'echo "127.0.0.1 project2.local" >> /etc/hosts'

curl http://project1.local
curl http://project2.local
cat /var/log/nginx/project1.access.log
cat /var/log/nginx/project2.access.log
```

**Output:**

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

<h1>Project 1</h1>
<h1>Project 2</h1>

127.0.0.1 - - [03/Jul/2026:17:49:58 +0000] "GET / HTTP/1.1" 200 19 "-" "curl/8.18.0"
127.0.0.1 - - [03/Jul/2026:17:49:58 +0000] "GET / HTTP/1.1" 200 19 "-" "curl/8.18.0"
```

(each log file contained only the request for its own site, confirming isolation)

**Explanation:**

Each virtual host is a separate `server { }` block matched by the `server_name`
directive against the incoming `Host` header — this is how one Nginx process on one
port serves entirely different content for different hostnames. Removing the
`default` config was necessary because Nginx otherwise uses the first-loaded
`server` block (alphabetically, `default` sorts before `project*`) as a fallback,
which would have masked the new virtual hosts.

**Result:** Homework 1 complete — both virtual hosts verified serving distinct
content with isolated access logs. See `NGINX_VHOSTS.md` for full configuration
documentation.

---

## Homework 2 — Nginx as a reverse proxy for Apache

### Goal

Install Apache, move it off port 80 (since Nginx already owns it), and configure
Nginx to transparently proxy all traffic to it, including a dedicated
`/health` endpoint answered directly by Nginx.

### Step 1 — Install and reconfigure Apache

**Commands:**

```bash
sudo apt install -y apache2
sudo systemctl status apache2 --no-pager
```

**Output (first attempt):**

```text
Active: failed (Result: exit-code)
apachectl[16595]: (98)Address already in use: AH00072: mak...:80
apachectl[16595]: no listening sockets available, shutting down
```

**Explanation:**

Apache failed to start because Nginx already had port 80 bound. This is expected —
resolved in the next step exactly as the lesson describes.

**Commands:**

```bash
sudo nano /etc/apache2/ports.conf   # Listen 80 → Listen 8080
sudo systemctl restart apache2
echo "ServerName localhost" | sudo tee /etc/apache2/conf-available/servername.conf
sudo a2enconf servername
sudo systemctl reload apache2
curl -I http://localhost:8080
```

**Output:**

```text
Active: active (running) since Fri 2026-07-03 17:51:44 UTC
Main PID: 17372 (apache2)

HTTP/1.1 200 OK
Server: Apache/2.4.66 (Ubuntu)
Content-Length: 10672
```

**Explanation:**

With Apache on 8080, both servers can coexist: Nginx owns port 80 (public), Apache
owns 8080 (internal only). The `ServerName localhost` fix also silenced the
`AH00558` FQDN warning covered in the lesson's troubleshooting section.

### Step 2 — Configure Nginx as reverse proxy

**Commands:**

```bash
sudo nano /etc/nginx/sites-available/apache_proxy.conf
sudo ln -s /etc/nginx/sites-available/apache_proxy.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

**Output:**

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

**Explanation:**

The config uses `listen 80 default_server;` rather than a specific `server_name`,
because this Nginx instance already serves `project1.local`/`project2.local` from
Homework 1 — `default_server` makes this block the fallback for any other
hostname (like `localhost`), matching the lesson's `upstream` + `proxy_pass`
pattern. Full config in `NGINX_REVERSE_PROXY.md`.

### Step 3 — Verification

**Commands:**

```bash
curl -v http://localhost
curl -v http://localhost/health
```

**Output:**

```text
< HTTP/1.1 200 OK
< Server: nginx/1.28.3 (Ubuntu)
< Content-Type: text/plain
healthy

(curl http://localhost returned Apache's full default HTML page, ~10,672 bytes,
 including Apache-specific content like the "Document Roots" section)
```

**Explanation:**

`http://localhost` returns Apache's own page content, but the `Server` header and
connection are with Nginx on port 80 — proof the request was transparently
forwarded to the backend and the response passed back through. `/health` never
touches Apache at all (`return 200` directly in the Nginx `location` block),
demonstrating how a reverse proxy can answer some paths itself while forwarding
others.

### Step 4 — Load test and log monitoring

**Commands:**

```bash
for i in {1..10}
do
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost
done
cat /var/log/nginx/apache_proxy.access.log
```

**Output:**

```text
200
200
200
200
200
200
200
200
200
200

127.0.0.1 - - [03/Jul/2026:17:56:48 +0000] "GET / HTTP/1.1" 200 10672 "-" "curl/8.18.0"
... (10 identical entries, one per request)
```

**Explanation:**

All ten requests succeeded with a consistent response size, confirming stable
proxying under repeated load. Every request appears in
`apache_proxy.access.log` (Nginx's log), not Apache's own log — from the client's
perspective, Apache is completely invisible; it's fully hidden behind the proxy.

**Result:** Homework 2 complete — Apache relocated to port 8080, Nginx
successfully proxying all traffic on port 80, health check endpoint verified,
10/10 requests returned `200` under a small load test. See
`NGINX_REVERSE_PROXY.md` for the full architecture diagram, header explanations,
and troubleshooting log.

---



