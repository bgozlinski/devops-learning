## Task 1 — Running a server and investigating the network

_Start a simple web server with Python's built-in module and investigate how it is reachable on the network._

**Commands:**

```bash
# Terminal 1 — start the server
mkdir ~/my-server && cd ~/my-server
echo "<h1>Gratulacje! Znalazles serwer!</h1>" > index.html
python3 -m http.server 8080

# Terminal 2 — investigate
curl http://localhost:8080
hostname -I
curl http://10.0.2.15:8080
ss -tulpn | grep 8080
```

**Output:**

```text
# curl http://localhost:8080
<h1>Gratulacje! Znalazles serwer </h1>

# hostname -I
10.0.2.15 172.17.0.1 fd17:625c:f037:2:a00:27ff:fe09:5ef7

# curl http://10.0.2.15:8080
<h1>Gratulacje! Znalazles serwer </h1>

# ss -tulpn | grep 8080
tcp   LISTEN 0   5   0.0.0.0:8080   0.0.0.0:*   users:(("python3",pid=4098,fd=3))
```

**Explanation:**

The server runs on **all network interfaces** (`0.0.0.0:8080`), which is why it responds identically whether queried through `localhost` (the loopback address `127.0.0.1`) or through the machine's private IP `10.0.2.15`. The `ss` output confirms a single `python3` process (PID 4098) listening on port 8080.

Of the three addresses returned by `hostname -I`, `10.0.2.15` is the private IPv4 address of the VM's NAT interface, `172.17.0.1` is the Docker bridge gateway, and `fd17:...` is a link-local IPv6 address. The content of the response does not differ between `localhost` and the private IP — and that is the point: binding to `0.0.0.0` exposes the server on every interface simultaneously. Had the server bound only to `127.0.0.1`, the request to `10.0.2.15:8080` would have failed with "connection refused."

---

## Task 2 — "Battle of ports"

_Attempt to start a second server on a port already in use, observe the error, identify what occupies the port, and resolve the conflict by using a different port._

**Commands:**

```bash
# Terminal 2 — try to reuse port 8080 (server from Task 1 still running)
cd /tmp && python3 -m http.server 8080

# Identify what holds the port
ss -tulpn | grep 8080
lsof -i :8080

# Resolve: start on a free port instead
cd /tmp && python3 -m http.server 8081
curl http://localhost:8081
```

**Output:**

```text
# Attempt to bind 8080 — fails:
OSError: [Errno 98] Address already in use

# ss -tulpn | grep 8080
tcp   LISTEN 0   5   0.0.0.0:8080   0.0.0.0:*   users:(("python3",pid=4098,fd=3))

# lsof -i :8080
COMMAND  PID   USER FD   TYPE DEVICE SIZE/OFF NODE NAME
python3 4098 bartek 3u  IPv4  28760      0t0  TCP *:http-alt (LISTEN)

# Second server on 8081 — succeeds:
Serving HTTP on 0.0.0.0 port 8081 (http://0.0.0.0:8081/) ...
127.0.0.1 - - [15/Jun/2026 16:03:42] "GET / HTTP/1.1" 200 -

# curl http://localhost:8081  → directory listing of /tmp (no index.html there)
```

**Explanation:**

A TCP port can be bound by only one listening socket at a time. The first server (PID 4098) already holds `0.0.0.0:8080`, so the second attempt fails with **`OSError: [Errno 98] Address already in use`** during the `server_bind()` call.

Both `ss` and `lsof` identify the same owner: the `python3` process with PID 4098. In `lsof`, `*:http-alt` is the symbolic name for port 8080.

The conflict is resolved by starting the second server on a free port, **8081**, which binds successfully. The `curl` to `localhost:8081` returns a directory listing of `/tmp` rather than the `Gratulacje` page, because this server was started from `/tmp`, which contains no `index.html` — so `http.server` falls back to listing the directory. This shows that `http.server` always serves the working directory it was launched from.

---

## Task 3 — "Map of network connections"

_Open several websites in a browser, find the active connections, and identify which remote ports are used for HTTPS (port 443)._

**Commands:**

```bash
# Open a few sites in the browser first, then:
ss -tunaep | grep ':443' | grep ESTAB | head -n 10
```

**Output (excerpt):**

```text
tcp ESTAB 0 0 10.0.2.15:52850      34.7.37.3:443  users:(("firefox",pid=9206,fd=433))
tcp ESTAB 0 0 10.0.2.15:54452  23.192.95.113:443  users:(("firefox",pid=9206,fd=480))
tcp ESTAB 0 0 10.0.2.15:47788 151.101.129.91:443  users:(("firefox",pid=9206,fd=317))
...
tcp TIME-WAIT 0 0 10.0.2.15:40960 216.239.32.36:443  timer:(timewait,19sec,0)
```

**Connection map:**

```text
Connection 1:
- Local address and port:  10.0.2.15:52850
- Remote address and port: 34.7.37.3:443
- State:                   ESTABLISHED
- Process:                 firefox (PID 9206)

Connection 2:
- Local address and port:  10.0.2.15:54452
- Remote address and port: 23.192.95.113:443
- State:                   ESTABLISHED
- Process:                 firefox (PID 9206)

Connection 3:
- Local address and port:  10.0.2.15:47788
- Remote address and port: 151.101.129.91:443
- State:                   ESTABLISHED
- Process:                 firefox (PID 9206)
```

**Explanation:**

All browser traffic to websites uses **remote port 443 (HTTPS)** — confirmed by every matching line ending in `:443`. The local ports (52850, 54452, 47788, …) are **ephemeral ports** assigned dynamically by the OS from the high range; each open tab/resource gets its own source port, which is why a single browser shows dozens of simultaneous connections to different servers. Every connection is owned by the same process, `firefox` (PID 9206).

The `ss` flags mean: `-t` TCP, `-u` UDP, `-n` numeric (no name resolution, so we see `443` not `https`), `-a` all sockets, `-e` extended info, `-p` owning process.

Two socket states appear in the output:

- **`ESTABLISHED`** — an active, open connection currently carrying data.
- **`TIME-WAIT`** (e.g. `216.239.32.36:443`) — a connection that has just been closed; the kernel keeps it briefly to ensure any late packets are handled before releasing the port.

The remote IP `151.101.129.91` belongs to Fastly's CDN range, illustrating that loading one webpage typically opens connections to many third-party servers (CDNs, analytics, fonts), not just the site's own domain.
