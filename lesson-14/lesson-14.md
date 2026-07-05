# Lesson 14 – Web Server Testing

## 1. Functional Testing (curl & wget)

### Server status check

```bash
sudo systemctl status nginx --no-pager
curl -I http://localhost/
```

Result: Nginx service `active (running)`, root page returns `HTTP/1.1 200 OK`.

### curl functional checks

| Test | Result |
|---|---|
| GET `/` | `200 OK` |
| Content-Type | `text/html` |
| GET `/nonexistent-page` | `404` (correct negative test) |
| DNS lookup | 0.000014 s |
| Connect time | 0.000126 s |
| TTFB | 0.001095 s |
| Total time | 0.001119 s |

The server responds correctly for both existing and non-existing resources, with sub-millisecond response times on localhost.

### wget check

```bash
wget -q --spider http://localhost/ && echo "Strona dostępna" || echo "Strona niedostępna"
```

Result: `Strona dostępna` — confirms the page is reachable without downloading content (spider mode).

## 2. Performance Testing with Apache Bench (ab)

Installed via `apache2-utils` (already present, version 2.3).

### Baseline test (100 requests, concurrency 10)

```bash
ab -n 100 -c 10 http://localhost/
```

| Metric | Value |
|---|---|
| Complete requests | 100 |
| Failed requests | 0 |
| Requests per second | 3375.53 [#/sec] |
| Time per request (mean) | 2.962 ms |
| P50 | 2 ms |
| P95 | 6 ms |
| P99 | 8 ms |

### Concurrency scaling test (1000 requests each)

```bash
ab -n 1000 -c 10  http://localhost/
ab -n 1000 -c 50  http://localhost/
ab -n 1000 -c 100 http://localhost/
ab -n 1000 -c 200 http://localhost/
```

| Concurrency | Complete requests | Failed requests | Requests/sec | Time/request (mean) |
|---|---|---|---|---|
| 10  | 1000 | 0 | 2119.40 | 4.718 ms |
| 50  | 1000 | 0 | 2753.08 | 18.161 ms |
| 100 | 1000 | 0 | 1932.11 | 51.757 ms |
| 200 | 1000 | 0 | 2088.85 | 95.747 ms |

**Observations:**
- No failed requests at any concurrency level (0% error rate up to 200 concurrent connections) — the static Nginx page handles the load without destabilizing.
- Throughput (RPS) stays in a similar range (~2000–2750 req/s) regardless of concurrency, indicating the bottleneck is CPU/single-core request processing rather than connection handling.
- Time per request increases roughly linearly with concurrency (from ~4.7 ms at c=10 to ~95.7 ms at c=200), as expected — more concurrent requests share the same processing capacity, so each individual request waits longer.
- No "breaking point" was observed in this range; a static test page like this scales very well under Nginx.

## 3. Performance Testing with Apache JMeter (headless)

Since the environment has no GUI, JMeter was installed and run in **non-GUI (headless) mode**, which is also the standard approach for CI/CD pipelines.

### Installation

```bash
sudo apt install -y default-jdk
java -version   # OpenJDK 25.0.3
wget https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-5.6.3.tgz
tar -xzf apache-jmeter-5.6.3.tgz
```

### Test Plan

A `.jmx` test plan was created manually (XML), consisting of:
- **Thread Group**: 50 threads (users), ramp-up 10 s, loop count 5 (→ 250 total requests)
- **HTTP Request Sampler**: `GET http://localhost:80/`
- **Summary Report Listener**

### Execution

```bash
./jmeter -n -t ~/simple_test.jmx -l ~/results.jtl -e -o ~/jmeter_report
```

### Results

| Metric | Value |
|---|---|
| Sample count | 250 |
| Error count / rate | 0 / 0.00% |
| Mean response time | 3.05 ms |
| Median (P50) | 2 ms |
| Min | 1 ms |
| Max | 52 ms |
| P90 | 4 ms |
| P95 | 6 ms |
| P99 | 16.39 ms |
| Throughput | 25.94 req/s |
| Received | 277.31 KB/s |
| Sent | 2.69 KB/s |

**Observations:**
- 0% error rate confirms functional correctness under a moderate load of 50 concurrent users.
- The gap between median (2 ms) and max (52 ms) suggests occasional outlier requests (likely JVM warm-up or first-connection overhead), but P99 (16.39 ms) shows the vast majority of requests were fast.
- Throughput here (~26 req/s) is much lower than `ab`'s (~2000+ req/s) because JMeter's thread ramp-up (10 s) and loop structure spread requests out over time, rather than firing them as fast as possible — this is expected and reflects a more "realistic user" load pattern vs. `ab`'s raw stress test.

## 4. Summary & Conclusions

- **Functional testing** (`curl`, `wget`) confirmed the Nginx server responds correctly to valid and invalid paths, with negligible local response times.
- **Apache Bench** load tests (10–200 concurrent connections, 1000 requests) showed **zero failed requests** and consistent throughput (~2000–2750 RPS), demonstrating the static page setup is robust under stress.
- **JMeter** headless test (50 users, 250 total requests) confirmed the same reliability (0% errors) with realistic ramp-up behavior, and provided percentile-based metrics (P50/P90/P95/P99) useful for SLA definition.
- No bottleneck or "breaking point" was reached in the tested concurrency range (up to 200), which is expected for a simple static page — a heavier target (a dynamic API endpoint, or the WordPress site from the earlier deployment) would be a better next candidate for stress/soak testing.

## Tools Used

- `curl` – functional/API testing, timing metrics
- `wget` – availability spider check
- `ab` (Apache Bench, apache2-utils 2.3) – quick load testing at varying concurrency
- Apache JMeter 5.6.3 (headless/non-GUI mode) – structured load test with Thread Group + HTTP Sampler + Summary Report