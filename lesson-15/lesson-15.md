# Lesson 15 – SSL/TLS Certificates

## Task 1: Generating a Private Key and Self-Signed Certificate with OpenSSL

### Private key generation

```bash
mkdir -p ~/ssl-lab && cd ~/ssl-lab
openssl genrsa -out server.key 2048
```

Result: 2048-bit RSA private key generated (`server.key`, permissions `600`).

### Certificate configuration and self-signed certificate

A config file (`openssl.cnf`) was created with subject fields (`C=PL`, `ST=Mazowieckie`, `L=Warszawa`, `O=Bartek DevOps Lab`, `CN=localhost`) and a Subject Alternative Name section (`DNS.1=localhost`, `IP.1=127.0.0.1`), then:

```bash
openssl req -new -x509 -key server.key -out server.crt -days 365 -config openssl.cnf
```

Certificate details:

| Field | Value |
|---|---|
| Signature Algorithm | sha256WithRSAEncryption |
| Subject / Issuer | `C=PL, ST=Mazowieckie, L=Warszawa, O=Bartek DevOps Lab, OU=IT, CN=localhost` |
| Validity | Jul 5 2026 → Jul 5 2027 (365 days) |
| Public Key | RSA 2048-bit |

### Key/certificate match verification

```bash
openssl x509 -noout -modulus -in server.crt | openssl md5
openssl rsa -noout -modulus -in server.key | openssl md5
```

Both commands returned the identical hash `1c9b4a69cc47b8093aaf17b976b6a27c`, confirming the certificate and private key form a valid matching pair.

## Task 2: Configuring Nginx with the Self-Signed Certificate

### Certificate deployment

```bash
sudo mkdir -p /etc/nginx/ssl
sudo cp ~/ssl-lab/server.key /etc/nginx/ssl/
sudo cp ~/ssl-lab/server.crt /etc/nginx/ssl/
sudo chmod 600 /etc/nginx/ssl/server.key
```

### Virtual host configuration (`/etc/nginx/sites-available/ssl-demo`)

```nginx
server {
    listen 80;
    server_name localhost;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name localhost;

    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

### Issue encountered: broken redirect line

**Problem:** initial `heredoc` paste inserted a stray backslash (`return 301 https://$host$request_uri\;`), causing:
```
nginx: [emerg] unexpected "}" in /etc/nginx/sites-enabled/ssl-demo:5
```
**Fix:** corrected the line with `sed`:
```bash
sudo sed -i 's/\$request_uri\\;/$request_uri;/' /etc/nginx/sites-available/ssl-demo
```
After the fix, `nginx -t` passed and the service restarted successfully.

### Issue encountered: conflicting server_name warning

```
nginx: [warn] conflicting server name "localhost" on 0.0.0.0:80, ignored
```
**Cause:** other vhosts from Lessons 13–14 (`project1.conf`, `project2.conf`, `apache_proxy.conf`) already listen on port 80 with `server_name localhost` (or as `default_server`), so this new vhost's port-80 block was ignored in favor of the pre-existing one. This is why the HTTP test below returned `200 OK` from the *other* vhost instead of a `301` redirect — confirmed by comparing the `ETag` value, which differed from `ssl-demo`'s expected response. The HTTPS (443) block was not affected since no other vhost was using port 443, and the certificate served correctly.
**Resolution:** not required for this lab (port 80 vhost precedence doesn't affect the SSL/TLS objective), but noted as a real-world lesson: server blocks on the same port need unique `server_name` values or explicit `default_server` designation to avoid ambiguity.

### HTTPS verification

```bash
curl -Ik https://localhost/
curl -kv https://localhost/ 2>&1 | grep -E "SSL connection|subject:|issuer:|expire"
openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | grep -E "Protocol|Cipher"
```

Result:

| Metric | Value |
|---|---|
| Negotiated protocol | **TLS 1.3** |
| Cipher suite | `TLS_AES_256_GCM_SHA384` (key exchange: X25519MLKEM768) |
| Certificate subject | `CN=localhost` (matches server) |
| Certificate expiry | Jul 5 2027 |
| HTTP status (HTTPS) | 200 OK |

The self-signed certificate is correctly served over TLS 1.3 with a strong AEAD cipher, confirming the Nginx SSL configuration works as intended (the port-80 redirect conflict aside).

## Task 3: Analyzing Real-World Certificates (Chain of Trust)

### Google.com certificate

```bash
openssl s_client -connect google.com:443 -servername google.com < /dev/null 2>/dev/null | openssl x509 -text > google_cert.txt
```

| Field | Value |
|---|---|
| Subject | `CN=*.google.com` |
| Issuer | `C=US, O=Google Trust Services, CN=WE2` |
| Validity | Jun 15 2026 → Sep 7 2026 (~84 days) |

Google uses its own intermediate CA (`WE2`, a "Google Trust Services" issuer) and a wildcard leaf certificate, with a short validity period typical of modern automated certificate issuance (comparable to Let's Encrypt's 90-day model).

### GitHub.com certificate (comparison)

```bash
openssl s_client -connect github.com:443 -servername github.com < /dev/null 2>/dev/null | openssl x509 -text > github_cert.txt
```

| Field | Value |
|---|---|
| Issuer | `C=GB, O=Sectigo Limited, CN=Sectigo Public Server Authentication CA DV E36` |
| Validity | Jul 3 2026 → Sep 30 2026 (~90 days) |

**Comparison:** Google uses its own private CA (Google Trust Services), while GitHub uses a third-party commercial CA (Sectigo, DV — Domain Validation). Both now issue short-lived certificates (~3 months), reflecting an industry-wide shift away from multi-year certificates toward frequent automated renewal — the same principle behind Let's Encrypt's 90-day certificates.

### Certificate chain analysis (google.com)

```bash
openssl s_client -connect google.com:443 -servername google.com -showcerts < /dev/null > google_chain.txt 2>/dev/null
grep -c "BEGIN CERTIFICATE" google_chain.txt
```

Result: **3 certificates** were sent in the chain (leaf `*.google.com` signed by intermediate `WE2`, plus at least one additional certificate in the chain — the server sends its own leaf + intermediate; the root is not included since it's already trusted in browsers/OS certificate stores, consistent with the lesson's chain-of-trust explanation).

### TLS version support

```bash
openssl s_client -connect google.com:443 -servername google.com -tls1_3 </dev/null 2>&1 | grep -E "Protocol|Cipher"
```

Result: Google negotiates **TLS 1.3** with cipher `TLS_AES_256_GCM_SHA384` — matching modern best practice.

An attempt to force TLS 1.0 (`-tls1`) did not produce the expected explicit rejection message; this is because OpenSSL 3.5.5 has dropped/deprecated client-side support for negotiating TLS 1.0 at the protocol level, so the flag is effectively a no-op rather than a meaningful test against the server. A more reliable way to confirm the server's minimum supported version would be an external tool such as SSL Labs' Server Test or `testssl.sh`, both referenced in the lesson materials.

## Summary & Conclusions

- Successfully generated an RSA 2048-bit key pair and a self-signed X.509 certificate with OpenSSL, and verified the key/certificate match via modulus hashing.
- Deployed the self-signed certificate on Nginx, achieving a working HTTPS endpoint negotiating **TLS 1.3** with a strong cipher suite.
- Encountered and resolved two real configuration issues: a stray-character syntax error in the vhost file, and a `server_name` conflict with pre-existing vhosts on port 80 — both common real-world Nginx pitfalls.
- Analyzed live certificates from google.com and github.com, confirming the chain-of-trust model described in the lesson (Root CA → Intermediate CA → Leaf), and observed that both major sites now use short-lived (~90-day) certificates, following the same automation-driven trend popularized by Let's Encrypt.
- Did not perform a live Let's Encrypt / Certbot issuance in this lab, since that requires a real, publicly resolvable domain with open ports 80/443 — this is a good candidate for the Ohana association's production server (`stowarzyszenie-ohana.pl`, already deployed on Hetzner behind Cloudflare) as a follow-up exercise, rather than the local lab VM.

## Tools Used

- `openssl genrsa` / `openssl req` / `openssl x509` – key and certificate generation/inspection
- `openssl s_client` – TLS handshake testing and remote certificate retrieval
- Nginx `ssl_certificate` / `ssl_certificate_key` directives – HTTPS server configuration
- `curl -k` / `curl -v` – HTTPS functional testing (ignoring self-signed cert trust for local testing)