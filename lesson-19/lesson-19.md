# Lesson 19 — Configuration Management, Part 2 (Ansible Roles, Environments, Best Practices)

## Task 1 — Creating and using roles (LAMP stack)

**Project:** `~/ansible-roles-project`

### Setup

```bash
mkdir -p ~/ansible-roles-project/{roles,group_vars} && cd ~/ansible-roles-project
```

`ansible.cfg`:

```ini
[defaults]
inventory = inventory.ini
roles_path = roles
host_key_checking = False
interpreter_python = /usr/bin/python3.14
```

Pinning `interpreter_python` silences the interpreter-discovery warning. Inventory targets localhost with `ansible_connection=local`; connectivity verified with `ansible local -m ping` → `pong`.

### Roles

Three roles scaffolded with `ansible-galaxy init roles/{apache,mysql,php}`, each with the standard directory structure (tasks, handlers, defaults, vars, templates, files, meta, tests).

**apache** — installs Apache, ensures it is running, creates the document root, deploys a Jinja2 virtual-host template (`vhost.conf.j2`), and enables the site with `a2ensite`. Idempotency of the `command` task is guaranteed with `args: creates:` (skips when the `sites-enabled` symlink exists). The handler uses `state: reloaded` — config reload without dropping connections. Defaults (`apache_domain`, `apache_document_root`, `apache_admin_email`, `apache_port`) are overridable from the playbook.

**mysql** — installs `mysql-server` + `python3-mysqldb`, creates a database and an application user. Final working task for the user:

```yaml
- name: Create MySQL user
  mysql_user:
    name: "{{ mysql_user }}"
    plugin: "{{ mysql_auth_plugin }}"        # caching_sha2_password
    plugin_auth_string: "{{ mysql_password }}"
    priv: "{{ mysql_db_name }}.*:ALL"
    host: localhost
    state: present
    login_unix_socket: /var/run/mysqld/mysqld.sock
  become: yes
```

**php** — installs PHP packages, notifies its own copy of a `restart apache` handler (handlers are scoped per role; a full restart is required to load `libapache2-mod-php`), and deploys an `info.php` test file from a template.

### Playbook

`site.yml` overrides role defaults via play `vars` (`lamp.local`, `lamp_db`, `lamp_user`), runs `pre_tasks` (apt cache update) → roles in order (apache, mysql, php) → `post_tasks` (index.html, `/etc/hosts` entry). Handlers fire at the end of the play.

### Problems encountered and fixes

| Problem | Cause | Fix |
|---|---|---|
| `Unable to acquire the dpkg frontend lock` | `unattended-upgrades` was running a large upgrade session (libc6, kernel, openssl, apache2, nginx) | Waited for it to finish, re-ran the playbook — idempotency makes re-runs safe. Never kill dpkg mid-run. |
| `unable to find /root/.my.cnf … Access denied for user 'root'@'localhost'` (1698) | Ubuntu MySQL root authenticates via `auth_socket`; the modules default to TCP | Added `login_unix_socket: /var/run/mysqld/mysqld.sock` to `mysql_db` / `mysql_user`; with `become: yes` the socket auth admits root without a password |
| `Plugin 'mysql_native_password' is not loaded` (1524) | MySQL 8.4+ removed `mysql_native_password`; supplying the `password` parameter forces the module down the legacy path even when `plugin` is set | Use only `plugin: caching_sha2_password` + `plugin_auth_string`, drop `password` entirely |
| `No package matching 'php-opcache' is available` | On Ubuntu resolute (PHP 8.5) `php-opcache` no longer exists (built into core); `php-json` is an empty transitional package (JSON in core since PHP 8) | Trimmed the package list to `php php-mysql php-cli php-common php-readline libapache2-mod-php` |

### Result

Final run: `ok=16 changed=7 failed=0`, handler `restart apache` executed. Verified:

```bash
curl http://lamp.local          # → "LAMP Stack is working!" page
curl http://lamp.local/info.php # → phpinfo() output
```

Re-running showed the apache role fully idempotent (all `ok`). One known cosmetic non-idempotency: `mysql_user` with `caching_sha2_password` reports `changed` on every run — the salted hash cannot be compared against the desired password, so the module re-sets it each time. Functionally harmless.

---

## Task 2 — Managing multiple environments

**Project:** `~/multi-env-project`

### Approach

The multi-directory pattern (lesson section 2.4): each environment gets its own inventory file **and** its own `group_vars/` next to it, which Ansible loads automatically. This eliminates the variable-conflict and alphabetical-priority problems of the single-inventory group approach.

```
environments/
├── dev/      inventory.ini + group_vars/{all,webservers,dbservers}.yml
├── staging/  inventory.ini + group_vars/{all,webservers,dbservers}.yml
└── prod/     inventory.ini + group_vars/{all,webservers,dbservers}.yml
```

Key idea: **group names are identical** (`webservers`, `dbservers`) across environments, so one playbook works everywhere — only the inventory changes. `ansible.cfg` defaults to the dev inventory (safe default); staging/prod require an explicit `-i`. Prod simulates scale with 2 host aliases per group.

Environment-specific values (excerpt):

| Variable | dev | staging | prod |
|---|---|---|---|
| `apache_port` | 8080 | 80 | 80 |
| `php_memory_limit` | 256M | 512M | 1024M |
| `mysql_max_connections` | 50 | 100 | 500 |
| `mysql_innodb_buffer_pool_size` | 256M | 512M | 4G |
| `backup_enabled` / frequency | false / — | true / daily | true / hourly |
| `debug_mode` | true | true | false |

Passwords from the lesson material were deliberately **omitted** — storing plaintext credentials in `group_vars` is exactly the anti-pattern the lesson warns about; in production they would go through Ansible Vault.

### Role and playbook

A `common` role creates per-environment directories (`/opt/<app>/<env>`, `/var/log/<app>/<env>`) and renders an `environment.conf` from the variables. Including `environment_name` in the paths lets all three "environments" coexist on the single lab machine. The playbook (`playbook/site.yml`) runs `common` on all hosts, then prints web/db variables per group with `debug`. `backup_frequency | default('n/a')` handles the optional variable that dev does not define.

### Runs

```bash
ansible-playbook playbook/site.yml                                       # dev (default)
ansible-playbook -i environments/staging/inventory.ini playbook/site.yml
ansible-playbook -i environments/prod/inventory.ini playbook/site.yml    # 4 host aliases
```

All three passed (`failed=0`). Tangible proof — three config files side by side:

```
/opt/my_application/development/environment.conf → DEBUG=true  MONITORING=false
/opt/my_application/staging/environment.conf     → DEBUG=true  MONITORING=true
/opt/my_application/production/environment.conf  → DEBUG=false MONITORING=true
```

Observation: since every alias resolves to the same localhost, tasks raced for shared resources — one alias reported `changed`, the rest `ok`. On real separate servers each would report `changed` independently.

---

## Task 3 — Best-practices project

**Project:** `~/best-practices-project` (git repository)

### Structure

```
├── ansible.cfg              # dev inventory default, retry files off, SSH pipelining
├── .gitignore               # *.retry, .vault_pass.txt, secrets.yml — before they exist
├── README.md
├── playbook/
│   ├── site.yml             # aggregator: import_playbook × 2
│   ├── webservers.yml / dbservers.yml
│   └── group_vars/all.yml   # shared across environments
├── inventories/{dev,prod}/hosts
└── roles/{common,web,db}/
```

New config options: `retry_files_enabled = False` (no `.retry` litter in the repo), `pipelining = True` (fewer SSH ops per task). Playbooks use the modern `ansible_facts["os_family"]` syntax instead of the deprecated injected `ansible_os_family` (ansible-core 2.20 deprecation warnings from Task 1). `cache_valid_time: 3600` skips apt cache updates fresher than an hour; `tags: always` on the pre_task guarantees the cache update even in tag-filtered runs.

### Error handling — block/rescue/always

The `common` role wraps its tasks in a block:

```yaml
- name: Configure common server settings
  block:
    - name: Install common packages
      apt: { name: "{{ common_packages }}", state: present }
      tags: [packages, common]
    - name: Configure NTP
      include_tasks: ntp.yml
      tags: [ntp, common]
  rescue:
    - debug: { msg: "Common configuration failed on {{ inventory_hostname }}!" }
    - debug: { msg: "Would send notification to admin (placeholder)" }
  always:
    - service: { name: ssh, state: started }
      tags: [services, common]
```

The rescue path was exercised **twice, on real failures**:

1. **`'common_packages' is undefined`** — `group_vars/` sat at the project root, but Ansible only auto-loads `group_vars` from next to the **inventory** or next to the **playbook**. Fix: `mv group_vars playbook/group_vars`. Both times the play continued (`failed=0, rescued=1`), the always section kept ssh running — exactly the graceful-degradation behavior blocks are for.
2. **`No package matching 'ntp' is available`** — Ubuntu resolute dropped the `ntp` package entirely. Fix: switched the role to **ntpsec** (package `ntpsec`, config `/etc/ntpsec/ntp.conf`, driftfile `/var/lib/ntpsec/ntp.drift`, service `ntpsec`); the handler kept its `restart ntp` name so `notify` references stayed intact. The `ntp.conf.j2` template (Jinja2 `{% for %}` over `ntp_servers`) worked unchanged.

Final clean run: `changed=3` on webserver (ntpsec install, template, handler restart), dbserver all `ok` — same localhost, webserver got there first.

### Tags

```bash
ansible-playbook playbook/site.yml --tags services
```

Ran only the 2 tagged tasks per host (+ facts + `always` pre_task): `ok=4` instead of 9+. Tag taxonomy: `common`, `web`, `db`, `packages`, `services`, `ntp`.

### Version control

Git identity configured (GitHub noreply email), initial commit of 35 files with project README documenting structure, usage per environment, and tags.
