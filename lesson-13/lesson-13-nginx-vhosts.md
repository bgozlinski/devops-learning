# NGINX_VHOSTS.md

Documentation for the Nginx virtual host setup created in Lesson 13, Homework 1 —
two independent sites (`project1.local`, `project2.local`) served from a single
Nginx instance on port 80.

## Configuration structure

```
/etc/nginx/
├── sites-available/
│   ├── project1.conf      # server block for project1.local
│   └── project2.conf      # server block for project2.local
└── sites-enabled/
    ├── project1.conf -> ../sites-available/project1.conf
    └── project2.conf -> ../sites-available/project2.conf

/var/www/
├── project1/
│   └── index.html
└── project2/
    └── index.html

/var/log/nginx/
├── project1.access.log / project1.error.log
└── project2.access.log / project2.error.log
```

Each site has its own `server { }` block, its own document root, and its own pair
of log files. Nginx picks the correct block to serve a request by matching the
`Host` header against each block's `server_name` directive — this is what allows
two sites to share port 80 on the same machine.

## Example vhost config

```nginx
server {
    listen 80;
    server_name project1.local;

    root /var/www/project1;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    access_log /var/log/nginx/project1.access.log;
    error_log /var/log/nginx/project1.error.log;
}
```

## How to add a new virtual host

1. Create the document root and content:
   ```bash
   sudo mkdir -p /var/www/newsite
   echo "<h1>New Site</h1>" | sudo tee /var/www/newsite/index.html
   ```
2. Create a new config file in `sites-available/`:
   ```bash
   sudo nano /etc/nginx/sites-available/newsite.conf
   ```
   Use the same template as above, changing `server_name` and `root`.
3. Enable it with a symlink into `sites-enabled/`:
   ```bash
   sudo ln -s /etc/nginx/sites-available/newsite.conf /etc/nginx/sites-enabled/
   ```
4. Test the syntax **before** reloading:
   ```bash
   sudo nginx -t
   ```
5. Reload Nginx (graceful, no downtime):
   ```bash
   sudo systemctl reload nginx
   ```
6. For local testing without real DNS, map the hostname to `127.0.0.1`:
   ```bash
   sudo bash -c 'echo "127.0.0.1 newsite.local" >> /etc/hosts'
   ```

## How to debug virtual host problems

- **Wrong site is served / default Nginx page shows up:**
  Check `ls -la /etc/nginx/sites-enabled/` — the config must be symlinked there,
  not just present in `sites-available/`. Also confirm the `default` config was
  removed, since it can act as a fallback and take priority.

- **`server_name` doesn't match the browser's request:**
  Nginx selects a server block by matching the `Host` header. If you're testing with
  `localhost` but `server_name` only lists `project1.local`, Nginx won't route to it.
  Add every hostname you'll test with, or use `server_name _;` as a catch-all.

- **See which config Nginx is actually using:**
  ```bash
  sudo nginx -T | less
  curl -H "Host: project1.local" http://127.0.0.1
  ```

- **Always validate syntax before reloading:**
  ```bash
  sudo nginx -t
  ```
  A syntax error here means `systemctl reload`/`restart` will fail — fix the file
  and re-test before trying again.

- **Check the error log first when something looks wrong:**
  ```bash
  sudo tail -20 /var/log/nginx/project1.error.log
  ```

## Verification performed

```bash
curl http://project1.local   # → <h1>Project 1</h1>
curl http://project2.local   # → <h1>Project 2</h1>
cat /var/log/nginx/project1.access.log   # 200, unique to project1
cat /var/log/nginx/project2.access.log   # 200, unique to project2
```

Both virtual hosts serve distinct content on the same port (80), each with an
isolated log file — confirming they are handled independently despite sharing the
same physical Nginx instance.