## Task 1 — Comprehensive network diagnostics

### Step 1 — Host availability (ping)

**Command:**

```bash
ping -c 4 example.com
```

**Output:**

```text
PING example.com (104.20.23.154) 56(84) bytes of data.
64 bytes from 104.20.23.154: icmp_seq=1 ttl=64 time=3.29 ms
64 bytes from 104.20.23.154: icmp_seq=2 ttl=64 time=4.39 ms
64 bytes from 104.20.23.154: icmp_seq=3 ttl=64 time=3.71 ms
64 bytes from 104.20.23.154: icmp_seq=4 ttl=64 time=7.05 ms
--- example.com ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3007ms
rtt min/avg/max/mdev = 3.292/4.610/7.053/1.463 ms
```

**Explanation:**

The host responds: 4 packets sent, 4 received, **0% loss**, average RTT ~4.6 ms — a healthy, low-latency path. The domain resolves to **`104.20.23.154`**, a **Cloudflare** address (104.20.x.x range). `example.com` is IANA's reserved documentation domain and is now served behind Cloudflare's CDN, which explains the very low latency.

### Step 2 — DNS analysis

**Commands:**

```bash
dig example.com
dig example.com +trace
nslookup example.com
```

**Output — `dig example.com` (ANSWER section):**

```text
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 17511
;; ANSWER SECTION:
example.com.    1   IN   A   104.20.23.154
example.com.    1   IN   A   172.66.147.243
;; SERVER: 127.0.0.53#53(127.0.0.53) (UDP)
```

**Output — `dig +trace` (delegation chain, condensed):**

```text
.            489102 IN NS a.root-servers.net. ... m.root-servers.net.   (13 root servers)
com.         172800 IN NS a.gtld-servers.net. ... m.gtld-servers.net.   (.com TLD servers)
example.com. 172800 IN NS hera.ns.cloudflare.com.
example.com. 172800 IN NS elliott.ns.cloudflare.com.
example.com. 300    IN A  104.20.23.154
example.com. 300    IN A  172.66.147.243
;; Received from hera.ns.cloudflare.com
```

**Output — `nslookup example.com`:**

```text
Non-authoritative answer:
Name: example.com   Address: 104.20.23.154
Name: example.com   Address: 172.66.147.243
Name: example.com   Address: 2606:4700:10::6814:179a
Name: example.com   Address: 2606:4700:10::ac42:93f3
```

**Explanation:**

- `dig` returns status **`NOERROR`** with **two A records** (`104.20.23.154`, `172.66.147.243`) — DNS load balancing / redundancy across Cloudflare edges. The answer came from the local stub resolver `127.0.0.53`. The TTL shown as `1` is a cached entry counting down toward expiry; the authoritative TTL is **300 s** (visible in the trace).
- `dig +trace` walks the full hierarchy: **root** (`.`, 13 servers) → **TLD** (`com.`, the gtld-servers) → **authoritative** (`hera`/`elliott.ns.cloudflare.com`), which return the final A records. The `RRSIG` and `DS` records at each level are **DNSSEC** signatures, establishing a chain of trust from the root down.
- `nslookup` confirms the same two IPv4 addresses plus two **IPv6 (AAAA)** addresses, all Cloudflare. "Non-authoritative answer" means it was served from the resolver cache.

The `communications error ... network unreachable` lines in the trace are cosmetic: `dig` attempted to reach a Cloudflare nameserver over IPv6, the VM has no usable IPv6 route, and it fell back to IPv4 successfully.

**Assigned IP:** `104.20.23.154` (+ second A record `172.66.147.243` and two AAAA records). **No errors** in the trace.

### Step 3 — HTTP / HTTPS connection

**Commands:**

```bash
curl -v http://example.com 2>&1 | head -n 30
curl -o /dev/null -s -w "HTTP code: %{http_code}\nTotal time: %{time_total}s\nDNS time: %{time_namelookup}s\nConnect time: %{time_connect}s\nTLS handshake: %{time_appconnect}s\n" https://example.com
```

**Output — `curl -v` (key lines):**

```text
* Trying [2606:4700:10::ac42:93f3]:80...
* connect to 2606:4700:10::ac42:93f3 port 80 ... failed: Connection refused
* Trying 104.20.23.154:80...
* Established connection to example.com (104.20.23.154 port 80)
> GET / HTTP/1.1
< HTTP/1.1 200 OK
< Server: cloudflare
< cf-cache-status: HIT
< CF-RAY: a0c2ebf19cf5bfe4-WAW
```

**Output — timing breakdown (HTTPS):**

```text
HTTP code: 200
Total time: 0.032666s
DNS time: 0.000901s
Connect time: 0.009136s
TLS handshake: 0.024885s
```

**Explanation:**

The site returns **`HTTP/1.1 200 OK`** served by `Server: cloudflare`. Two informative headers: `cf-cache-status: HIT` (served from Cloudflare's cache, not the origin) and `CF-RAY: ...-WAW`, where **WAW = Warsaw** — the Cloudflare datacenter serving the request, which is why latency is only a few milliseconds.

Timing for HTTPS: DNS lookup **0.9 ms** (cached), TCP connect **9.1 ms**, TLS handshake complete at **24.9 ms**, total **32.7 ms**. The TLS handshake is the largest single component (~16 ms on top of the TCP connect), which is typical, as it involves the certificate exchange and key negotiation. (The initial IPv6 `Connection refused` is the same harmless IPv6-fallback behavior.)

### Step 4 — Mail servers (MX)

**Command:**

```bash
dig example.com MX
```

**Output:**

```text
;; ->>HEADER<<- opcode: QUERY, status: NOERROR
;; ANSWER SECTION:
example.com.   300   IN   MX   0 .
```

**Explanation:**

The record `MX 0 .` (priority 0, target = a single dot) is a **"Null MX" record** (RFC 7505). It is an explicit, standards-compliant declaration that **the domain accepts no email** — there is no mail server and senders should not attempt delivery. This is not a misconfiguration; `example.com` is a reserved documentation domain that deliberately handles no mail.

### Step 5 — Findings summary

|Stage|Result|Time|
|---|---|---|
|ICMP (ping)|Reachable, 0% loss|~4.6 ms avg|
|DNS (dig)|`NOERROR`, 2× A + 2× AAAA (Cloudflare)|TTL 300 s|
|HTTP|`200 OK`, served from Cloudflare Warsaw edge|—|
|HTTPS|`200 OK`|32.7 ms total|
|MX|Null MX (`0 .`) — no mail accepted|—|

**Conclusion regarding the reported symptom:** The reported scenario ("page does not load, but email works") does **not** match reality for `example.com`. In the actual diagnostics the page **does** load (HTTP/HTTPS `200 OK`), and email is **explicitly disabled** by a Null MX record — the opposite of the complaint. This illustrates an important diagnostic principle: the tools document what is actually happening, which may contradict the user's description, and the report reflects the measured facts.

### Advanced — Comparison with a non-existent domain

**Commands:**

```bash
ping -c 2 example-nonexistent-12345.com
dig example-nonexistent-12345.com
curl -v http://example-nonexistent-12345.com 2>&1 | head -n 10
```

**Output:**

```text
# ping
ping: example-nonexistent-12345.com: Name or service not known

# dig
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 23805
;; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 0, ADDITIONAL: 1

# curl
* Could not resolve host: example-nonexistent-12345.com
* Store negative name resolve for example-nonexistent-12345.com:80
curl: (6) Could not resolve host: example-nonexistent-12345.com
```

**Explanation:**

Every tool fails at the **DNS resolution stage**, before any network connection is attempted:

- **ping** → `Name or service not known`. No IP is ever obtained, so no packets are sent. This is distinct from a reachability failure ("host not responding").
- **dig** → status **`NXDOMAIN`** with `ANSWER: 0` — the authoritative "this domain does not exist" response. Contrast with `example.com`, which returned `NOERROR` and real answers.
- **curl** → `Could not resolve host`, exit code **6** (curl's specific "couldn't resolve host" code). It also logs `Store negative name resolve` — the resolver caches the negative result (negative caching) to avoid repeated lookups.

**Key difference:** A working domain resolves (`NOERROR` + IPs) and any failure then occurs at the network or HTTP layer. A non-existent domain fails immediately at DNS (`NXDOMAIN`), and every downstream tool stops there because there is no IP to act on. **The stage at which the failure occurs is what distinguishes a DNS problem from a connectivity problem.**

---

## Task 2 — Configuring and testing CORS

### Step 1 — Start a local HTTP server

**Command:**

```bash
cd ~/my_project
python3 -m http.server 8000
```

### Step 2 — Send a simulated cross-origin preflight

**Command (second terminal):**

```bash
curl -X OPTIONS \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: GET" \
  -v http://localhost:8000 2>&1 | head -n 30
```

**Output (key lines):**

```text
> OPTIONS / HTTP/1.1
> Host: localhost:8000
> Origin: http://localhost:3000
> Access-Control-Request-Method: GET
>
< HTTP/1.0 501 Unsupported method ('OPTIONS')
< Server: SimpleHTTP/0.6 Python/3.14.4
< Connection: close
< Content-Type: text/html;charset=utf-8
< Content-Length: 485
```

### Step 3 — Analysis

The preflight request was sent correctly, including the `Origin` and `Access-Control-Request-Method` headers. The response reveals the finding:

- **Are CORS headers set?** No — there is not a single `Access-Control-Allow-*` header in the response.
- **Does `python3 -m http.server` support CORS?** No. It is a minimal static file server (`SimpleHTTP/0.6`) with no CORS awareness. It does not even implement the `OPTIONS` method, so it rejects the preflight outright with **`501 Unsupported method ('OPTIONS')`**.
- **What would you change to support CORS?** Use something that adds `Access-Control-Allow-Origin` (and related headers) and answers the `OPTIONS` preflight with `200`/`204`. Options:
    - Put a reverse proxy such as **Nginx** in front and add the headers there.
    - Use a real framework — **Express** with the `cors` middleware, or **Flask-CORS**.
    - In Python, subclass `SimpleHTTPRequestHandler` and override `do_OPTIONS()` to inject the CORS headers.

(The initial `::1 connection refused` followed by IPv4 fallback is the standard harmless IPv6-loopback behavior in this VM.)

### Step 4 — What is CORS?

**What it is:** CORS (Cross-Origin Resource Sharing) is a browser security mechanism that controls whether a web page loaded from one origin (scheme + host + port) is allowed to make requests to a _different_ origin. The server signals permission through `Access-Control-Allow-*` response headers; if they are absent or do not match, the browser blocks the response from reaching the page's JavaScript.

**When it is needed:** Whenever a frontend served from one origin (e.g. `http://localhost:3000`) calls an API on another origin (e.g. `http://api.example.com` or even the same host on a different port). For "non-simple" requests (custom headers, methods like `PUT`/`DELETE`, certain content types), the browser first sends a **preflight** `OPTIONS` request to ask the server what is allowed before sending the real request.

**Why browsers enforce it:** To protect users. Without it, a malicious site could silently issue requests to another site where the user is logged in (e.g. their bank) and read the responses using the user's credentials/cookies. CORS makes cross-origin access **opt-in by the target server** — the server must explicitly grant permission, so a third-party site cannot read protected data on the user's behalf unless allowed.

It is important to note that **CORS is enforced by browsers, not by command-line tools**. That is why `curl` could send the cross-origin request freely above — the policy only restricts JavaScript running inside a browser.