# Lesson 18 — Configuration Management Part 1: Ansible

## Homework 1: LAMP Stack Deployment with Ansible Roles

### Project Structure

```
~/ansible-lamp/
├── ansible.cfg          # inventory path, host_key_checking off
├── inventory.ini        # environment groups (see Homework 2)
├── site.yml             # main playbook: roles + verification post_tasks
├── README.md            # usage instructions
├── group_vars/          # per-environment variables (Homework 2)
│   ├── dev.yml  staging.yml  prod.yml
└── roles/
    ├── base/      # apt cache update, common packages
    ├── web/       # Apache: install, listen port, service (+ handler)
    ├── database/  # MySQL: install, app DB, user, seed data, env tuning (+ handler)
    ├── php/       # PHP + libapache2-mod-php + php-mysql
    └── app/       # PHP demo app, Jinja2 vhost, site enablement (+ handler)
```

Each role follows the standard layout: `tasks/`, `defaults/`, `handlers/`, `templates/`.

### Key Implementation Points

**Roles and separation of concerns.** Each LAMP component is an independent role with its own default variables (`db_name`, `apache_port`, `app_dir`, …) so the playbook stays a thin composition layer:

```yaml
- name: Deploy LAMP stack
  hosts: "{{ target_env | default('dev') }}"
  roles:
    - { role: base,     tags: [base] }
    - { role: web,      tags: [web] }
    - { role: database, tags: [database] }
    - { role: php,      tags: [php] }
    - { role: app,      tags: [app] }
```

**Handlers.** Configuration changes (`ports.conf`, vhost, PHP module, MySQL env config) trigger `restart apache` / `restart mysql` handlers — services restart only when something actually changed.

**Templates (Jinja2).** The PHP application, the Apache vhost, and the MySQL tuning file are generated from templates and parametrized with role defaults, environment variables, and Ansible facts (`ansible_hostname`, `ansible_date_time`).

**Database provisioning.** The `database` role creates the application database and user with `community.mysql.*` modules and seeds a `visitors` table. The demo PHP app inserts a row per visit and displays the row count, proving the PHP → MySQL connection end-to-end:

```
<h1>LAMP demo deployed by Ansible</h1>
<p>Environment: production</p>
<p>Host: linux1 | PHP 8.5.4</p>
<p>DB connection OK — visitors rows: 3</p>
```

### Idempotency

The first run reported `changed=8`; achieving `changed=0` on re-runs required handling three non-idempotent spots:

1. **`a2ensite`/`a2dissite`** (command module) — `changed_when: "'already' not in a2_result.stdout"` so an already-enabled site reports `ok`.
2. **Seeding data** — `INSERT ... SELECT ... WHERE NOT EXISTS` in SQL plus `changed_when: (seed_result.rowcount | sum) > 0` for the `mysql_query` task.
3. **`mysql_user` with `caching_sha2_password`** — the hash uses a random salt, so the module cannot compare states and always reports `changed`. Fix: a static 20-character `salt` makes the hash deterministic.

Final verification: `PLAY RECAP ... ok=16 changed=0 failed=0`.

---

## Homework 2: Multi-Environment Configuration

### Environment Variables (`group_vars/`)

| Setting | dev | staging | prod |
|---|---|---|---|
| `app_environment` | development | staging | production |
| `apache_port` | 8081 | 8082 | 80 |
| `php_display_errors` | On | Off | Off |
| `apache_keepalive` | Off | On | On |
| `db_max_connections` | 50 | 100 | 200 |

Development favours debuggability (errors displayed), production favours performance and stricter settings — applied through the vhost template (`php_admin_flag display_errors`, `KeepAlive`) and a generated MySQL drop-in (`/etc/mysql/mysql.conf.d/zz_ansible_env.cnf` with `max_connections`).

### Inventory Design — One Machine, Three Environments

A subtle trap: putting the *same host* in all three groups makes Ansible merge every group's variables for that host (alphabetically last group wins), regardless of `--limit`. The fix is one **inventory alias per environment**, all pointing at the same address:

```ini
[dev]
lamp-dev ansible_host=127.0.0.1 ansible_connection=local
[staging]
lamp-staging ansible_host=127.0.0.1 ansible_connection=local
[prod]
lamp-prod ansible_host=127.0.0.1 ansible_connection=local
```

Each alias receives only its own group's variables.

### Environment Switching and Tags

```bash
ansible-playbook site.yml -e target_env=prod          # choose environment on the CLI
ansible-playbook site.yml -e target_env=dev --tags web,app   # run selected roles only
ansible-playbook site.yml -e target_env=prod --tags test     # run only the tests
```

`hosts: "{{ target_env | default('dev') }}"` selects the inventory group; every role carries a tag.

### Automated Tests (`post_tasks`)

Three verification tasks run after deployment, tagged `test`:

1. `wait_for` — Apache listens on the environment-specific port,
2. `uri` — fetch the application page,
3. `assert` — the page contains `DB connection OK` **and** the expected `app_environment` string.

Results:

```
"msg": "Environment development verified on port 8081"
"msg": "Environment production verified on port 80"
```

The tag-only run (`--tags test`) executed 4 tasks with `changed=0`, confirming tests are side-effect-free.

---

## Common Errors Encountered

| Error | Cause | Fix |
|---|---|---|
| `Timed out waiting for become success or become password prompt` | VM's sudo/PAM printed a second `Password:` prompt that Ansible's become plugin cannot answer | Passwordless sudo for the lab user (`/etc/sudoers.d/bartek`, `NOPASSWD:ALL`) — standard practice for Ansible-managed hosts |
| `Plugin 'mysql_native_password' is not loaded` | MySQL 8.4+ removed the legacy auth plugin that `mysql_user` defaults to | `plugin: caching_sha2_password` + `plugin_auth_string` |
| `mysql_user` always `changed` | Random salt in `caching_sha2_password` hashing → state comparison impossible | Static `salt:` parameter |
| Apache would not bind port 80 | nginx from Lesson 13 still occupied the port | `systemctl disable --now nginx` |
| All group variables merged despite `--limit` | Same inventory hostname in multiple groups | Per-environment host aliases with `ansible_host` |

## Summary

* Built a fully role-based LAMP deployment (base, web, database, php, app) with handlers, Jinja2 templates, default variables, and a working PHP → MySQL demo application.
* Achieved true idempotency (`changed=0` on re-run) by fixing three non-idempotent patterns: command-module site enablement, SQL seeding, and MySQL 8.4 password hashing.
* Extended the project to three environments (dev/staging/prod) with distinct ports, debug settings, and database tuning, switchable from the command line, with tag-based selective execution and assert-based post-deployment tests verifying each environment.