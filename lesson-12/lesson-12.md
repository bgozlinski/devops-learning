# Lesson 12 — Bash in Practice: From Basics to Advanced

## Homework 1 — `service_ctl.sh` (background service management)

### Goal

Write a script managing a simulated background service (a `sleep` process),
supporting `start`, `stop`, `restart`, and `status`, using a PID file, `kill -0`
liveness checks, leveled logging with timestamps, and `trap cleanup EXIT`.

### Step 1 — Script creation

**Command:**

```bash
mkdir -p ~/lesson12_bash
cd ~/lesson12_bash
nano service_ctl.sh
chmod +x service_ctl.sh
```

**Verification:**

```text
-rwxrwxr-x 1 bartek bartek 2396 Jun 15 19:58 service_ctl.sh
```

**Explanation:**

The script structures commands with a top-level `case "${1:-}"` dispatcher
(`start|stop|restart|status`), using `${1:-}` so an empty argument list doesn't
trigger `set -u`-style unbound variable errors. `log()` writes INFO to stdout and
ERROR to stderr (`>&2`), each with a `date '+%Y-%m-%d %H:%M:%S'` timestamp, and
`trap cleanup EXIT` removes a stale PID file only if the process it points to is
confirmed dead — preventing legitimate running services from losing their PID file.

### Step 2 — `start` and `status`

**Command:**

```bash
./service_ctl.sh start
./service_ctl.sh status
```

**Output:**

```text
[2026-06-15 19:58:40] [INFO] Usługa uruchomiona (PID: 118415)
[2026-06-15 19:58:40] [INFO] Usługa działa (PID: 118415)
```

**Explanation:**

`start_service()` launches `sleep 1000 &` in the background, captures its PID with
`$!`, and writes it to `service.pid`. `status_service()` reads that PID back and
confirms liveness with `kill -0 "$pid" 2>/dev/null` — signal `0` performs no actual
kill, only an existence check, returning exit status `0` if the process is alive.

### Step 3 — Duplicate `start` and `restart`

**Command:**

```bash
./service_ctl.sh start
./service_ctl.sh restart
./service_ctl.sh status
```

**Output:**

```text
[2026-06-15 19:58:57] [ERROR] Usługa już działa (PID: 118415)
[2026-06-15 19:58:57] [INFO] Usługa zatrzymana (PID: 118415)
[2026-06-15 19:58:58] [INFO] Usługa uruchomiona (PID: 118572)
[2026-06-15 19:58:58] [INFO] Usługa działa (PID: 118572)
```

**Explanation:**

A second `start` is correctly rejected because the existing PID (118415) is still
alive. `restart` calls `stop_service()` then `start_service()` in sequence, resulting
in a fresh process (PID 118572) — confirming the PID file and process ID are updated
together and stay in sync.

### Step 4 — `stop`, `status`, and log review

**Command:**

```bash
./service_ctl.sh stop
./service_ctl.sh status
cat service.log
```

**Output:**

```text
[2026-06-15 19:59:10] [INFO] Usługa zatrzymana (PID: 118572)
[2026-06-15 19:59:10] [INFO] Usługa nie jest uruchomiona
```

(full `service.log` contains the complete chronological history of every start,
duplicate-rejection, restart, and stop action, each with its own timestamp)

**Explanation:**

`stop_service()` sends a normal `kill` (SIGTERM) to the tracked PID and removes the
PID file unconditionally on success. A subsequent `status` correctly reports the
service as not running since no PID file remains. `tee -a` inside `log()` writes
every message to both the terminal and the persistent `service.log` file
simultaneously.

**Result:** Homework 1 complete — full service lifecycle (start / duplicate
rejection / restart / stop / status) verified with correct PID tracking, leveled
logging, and cleanup.

---

## Homework 2 — `backup.sh` (backup script with CLI options)

### Goal

Extend the Lesson 12 backup example with `case`/`shift`-based option parsing
(`-s` source, `-d` destination, `-v` verbose, `-h` help), `set -euo pipefail`,
directory validation, leveled logging, and `trap cleanup EXIT` for temp file cleanup.

### Step 1 — Script creation

**Command:**

```bash
nano backup.sh
chmod +x backup.sh
```

**Verification:**

```text
-rwxrwxr-x 1 bartek bartek 2425 Jun 15 19:59 backup.sh
```

**Explanation:**

`set -euo pipefail` at the top of the script means: stop on any unhandled command
failure (`-e`), treat unset variables as errors (`-u`), and propagate failures through
pipes (`-o pipefail`). A `mktemp` temp file tracks the last backup path, and
`trap cleanup EXIT` guarantees it's removed regardless of how the script exits —
success, validation failure, or an unexpected error.

### Step 2 — Help flag

**Command:**

```bash
./backup.sh -h
```

**Output:**

```text
Użycie: ./backup.sh -s <source_dir> -d <backup_dir> [-v] [-h]

Opcje:
  -s DIR   Katalog źródłowy (wymagany)
  -d DIR   Katalog docelowy na backup (wymagany)
  -v       Tryb szczegółowy (verbose)
  -h       Wyświetl tę pomoc
```

**Explanation:**

The `-h` case calls `usage()` directly, which prints a heredoc-based help block and
exits with status `0` — following the same Unix convention as `project_setup.sh`
from Lesson 11: help output is not an error condition.

### Step 3 — Missing required options

**Command:**

```bash
./backup.sh
./backup.sh -s /tmp/test_source
```

**Output:**

```text
[ERROR] Wymagane są opcje -s i -d
Użycie: ./backup.sh -s <source_dir> -d <backup_dir> [-v] [-h]
...
```

(both invocations produce the same error + usage output)

**Explanation:**

After the `while [[ $# -gt 0 ]]; do case "$1" in ... esac; done` parsing loop
finishes, an explicit check (`[[ -z "$source_dir" || -z "$backup_dir" ]]`) catches
any missing required option — regardless of which one is missing — before any
filesystem operation is attempted.

### Step 4 — Full backup run with `-v`

**Command:**

```bash
mkdir -p /tmp/test_source /tmp/test_backup
echo "test" > /tmp/test_source/file.txt
./backup.sh -s /tmp/test_source -d /tmp/test_backup -v
```

**Output:**

```text
[2026-06-15 20:00:37] [INFO] Rozpoczęcie tworzenia kopii zapasowej z /tmp/test_source do /tmp/test_backup/backup_20260615_200037.tar.gz
[2026-06-15 20:00:37] [INFO] Kopia zapasowa utworzona: /tmp/test_backup/backup_20260615_200037.tar.gz
[2026-06-15 20:00:37] [INFO] Proces zakończony sukcesem
Backup utworzony: /tmp/test_backup/backup_20260615_200037.tar.gz
[2026-06-15 20:00:37] [INFO] Pliki tymczasowe usunięte
```

**Explanation:**

Because `verbose=1` (`-v`), every INFO-level log line is printed (INFO is
conditional on `$verbose` in this script, unlike ERROR which always prints to
stderr). `tar -czf ... -C "$source_dir" .` changes into the source directory before
archiving, so the resulting `.tar.gz` contains relative paths — easier to restore
into any target location later. `trap cleanup EXIT` fires automatically at the end,
removing the temp file used to pass the backup path between functions.

### Step 5 — Archive verification and failure path

**Command:**

```bash
ls -la /tmp/test_backup/
tar -tzf /tmp/test_backup/backup_*.tar.gz
./backup.sh -s /tmp/nieistniejacy -d /tmp/test_backup -v
```

**Output:**

```text
-rw-rw-r-- 1 bartek bartek 154 Jun 15 20:00 backup_20260615_200037.tar.gz

./
./file.txt

[2026-06-15 20:00:51] [ERROR] Katalog źródłowy nie istnieje: /tmp/nieistniejacy
[2026-06-15 20:00:51] [INFO] Pliki tymczasowe usunięte
```

**Explanation:**

`tar -tzf` confirms the archive contains relative paths (`./file.txt`), not absolute
ones — the `-C` flag worked as intended. The failure-path test confirms two things
at once: `check_directories()` correctly rejects a non-existent source directory with
an ERROR log before any `tar` command runs, and — critically — `trap cleanup EXIT`
still fires and removes the temp file even though the script exited via `exit 1`,
proving the cleanup mechanism is failure-safe as required by the lesson's grading
criteria.

**Result:** Homework 2 complete — option parsing, help, validation, verbose
logging, successful backup with relative paths, and failure-path cleanup all
verified.
