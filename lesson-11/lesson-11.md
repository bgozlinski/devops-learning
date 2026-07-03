
## Homework 1 — Extended `project_setup.sh`

### Step 1 — Script creation

**Command:**

```bash
mkdir -p ~/lesson11_bash
cd ~/lesson11_bash
nano project_setup.sh
chmod +x project_setup.sh
```

**Verification:**

```bash
ls -la
cat project_setup.sh | head -5
```

```text
-rw-rw-r-- 1 bartek bartek 3213 Jun 15 19:38 project_setup.sh

#!/bin/bash
# project_setup.sh - Tworzenie struktury projektu (wersja rozszerzona)
# Użycie: ./project_setup.sh <nazwa_projektu> <język> [katalogi_csv]
log_action() {
```

**Explanation:**

The script uses three helper functions — `create_dir()`, `create_gitignore()`, and `create_main_file()` — plus `log_action()` for timestamped logging to `<project_name>/setup.log`. Language validation is done with a `for` loop over an `allowed_langs` array before any directory is touched.

### Step 2 — Validation: no arguments and `--help`

**Command:**

```bash
./project_setup.sh
./project_setup.sh --help
```

**Output:**

```text
Użycie: ./project_setup.sh <nazwa_projektu> <język> [katalogi]
Użycie: ./project_setup.sh <nazwa_projektu> <język: python|js|go> [katalogi_csv]
```

**Explanation:**

`[[ $# -lt 2 ]]` catches missing arguments before the script tries to use them, exiting with status `1`. The `--help` flag is checked first and exits with status `0`, following the Unix convention that help output is not an error.

### Step 3 — Full run

**Command:**

```bash
./project_setup.sh test_proj python "src,tests,api"
```

**Output:**

```text
[OK] Utworzono katalog test_proj
[OK] Utworzono katalog test_proj/src
[OK] Utworzono katalog test_proj/tests
[OK] Utworzono katalog test_proj/api
[OK] Utworzono .gitignore dla python
[OK] Utworzono plik startowy dla python
Initialized empty Git repository in /home/bartek/lesson11_bash/test_proj/.git/
[OK] Zainicjalizowano repozytorium Git
[SUCCESS] Projekt test_proj został pomyślnie utworzony!
```

**Explanation:**

The custom directory list (`$3`) is split on commas with `IFS=',' read -ra dirs_array <<< "$custom_dirs"`, then iterated with a `for` loop to create each subdirectory. Git printed a standard hint about the default branch name (`master` vs. future `main`) — informational only, not an error.

### Step 4 — Output verification

**Command:**

```bash
ls -la test_proj/
cat test_proj/.gitignore
cat test_proj/src/main.py
cat test_proj/setup.log
```

**Output:**

```text
drwxrwxr-x 6 bartek bartek 4096 Jun 15 19:39 .
drwxrwxr-x 6 bartek bartek 4096 Jun 15 19:39 .git
-rw-rw-r-- 1 bartek bartek   38 Jun 15 19:39 .gitignore
drwxrwxr-x 2 bartek bartek 4096 Jun 15 19:39 api
-rw-rw-r-- 1 bartek bartek  507 Jun 15 19:39 setup.log
drwxrwxr-x 2 bartek bartek 4096 Jun 15 19:39 src
drwxrwxr-x 2 bartek bartek 4096 Jun 15 19:39 tests

__pycache__/
*.pyc
.venv/
*.egg-info/

print("Hello from test_proj")

2026-06-15 19:39:21 - Created directory: test_proj
2026-06-15 19:39:21 - Setup started for project: test_proj (lang: python)
2026-06-15 19:39:21 - Created directory: test_proj/src
2026-06-15 19:39:21 - Created directory: test_proj/tests
2026-06-15 19:39:21 - Created directory: test_proj/api
2026-06-15 19:39:21 - Created .gitignore for language: python
2026-06-15 19:39:21 - Created starter file for python
2026-06-15 19:39:21 - Git repository initialized
2026-06-15 19:39:21 - Setup finished successfully
```

**Explanation:**

All four requested directories exist, the Python `.gitignore` contains the correct entries (`__pycache__/`, `*.pyc`, `.venv/`, `*.egg-info/`), the starter `main.py` references the project name, and `setup.log` shows a complete, chronologically ordered audit trail of every action taken.

### Step 5 — Language validation

**Command:**

```bash
./project_setup.sh test_proj2 ruby
```

**Output:**

```text
[ERROR] Nieobsługiwany język: ruby (dozwolone: python js go)
```

**Explanation:**

Because the language check runs before `create_dir()` is called for the project root, an invalid language is rejected cleanly with no filesystem side effects at all — no partial project directory is left behind.

**Result:** ✅ Homework 1 complete — all functionality (argument handling, `.gitignore` generation, starter file, logging, language validation, `--help`) verified.

---

## Homework 2 — `log_analyzer.sh`

### Goal

Build a log analysis script that filters a log file by a search pattern, counts matches, reports the top 5 most frequent words among matched lines, and writes results to `report.txt`. Implemented via three functions: `validate_input()`, `search_logs()`, `generate_report()`.

### Step 1 — Script creation and test log

**Command:**

```bash
nano log_analyzer.sh
chmod +x log_analyzer.sh
cat > test.log << 'EOF'
2026-06-15 10:00:01 INFO User login successful
2026-06-15 10:01:15 ERROR Failed to connect to database
2026-06-15 10:02:30 INFO Request processed
2026-06-15 10:03:45 ERROR Failed authentication for user admin
2026-06-15 10:04:12 WARNING Disk usage high
2026-06-15 10:05:00 ERROR Failed to write to log file
2026-06-15 10:06:22 INFO User logout
2026-06-15 10:07:33 ERROR Connection timeout
EOF
```

**Verification:**

```text
-rwxrwxr-x  1 bartek bartek 2005 Jun 15 19:40 log_analyzer.sh
-rw-rw-r--  1 bartek bartek  389 Jun 15 19:40 test.log
```

**Explanation:**

A local 8-line test log (4× `ERROR`, 2× `INFO`, 1× `WARNING`) was used instead of a system log to avoid needing `sudo` and to keep results reproducible.

### Step 2 — Filtering run

**Command:**

```bash
./log_analyzer.sh test.log ERROR 3
```

**Output:**

```text
[INFO] Znaleziono 4 wystąpień wzorca 'ERROR'
[OK] Raport zapisany do report.txt
```

**Explanation:**

`search_logs()` reads the file line by line with `while IFS= read -r line`, checks each line with a `[[ "$line" == *"$pattern"* ]]` glob match, increments a total counter (`match_count`) for every hit, and separately caps the _stored_ lines at the `max_results` limit (`$3`, default 10) — so the reported total (4) and the displayed subset (3) can correctly differ.

### Step 3 — Report content

**Command:**

```bash
cat report.txt
```

**Output:**

```text
=== Raport analizy logów ===
Plik źródłowy: test.log
Wzorzec: ERROR
Data analizy: 2026-06-15 19:40:59
Liczba znalezionych linii: 4

--- Dopasowane linie (max 3) ---
2026-06-15 10:01:15 ERROR Failed to connect to database
2026-06-15 10:03:45 ERROR Failed authentication for user admin
2026-06-15 10:05:00 ERROR Failed to write to log file

--- Top 5 najczęstszych słów w dopasowanych liniach ---
      4 to
      3 Failed
      3 ERROR
      3 2026-06-15
      1 write

Czas wykonania skryptu: 0s
```

**Explanation:**

`generate_report()` writes a structured report using a single `{ ... } > report.txt` block. The word frequency table is produced with a classic Unix pipeline — `tr -s ' ' '\n' | sort | uniq -c | sort -rn | head -5` — matching the "do one thing well" pipe philosophy from the lesson's introduction. `$SECONDS` provides the script's elapsed runtime for free, without any manual timing code.

### Step 4 — Input validation

**Command:**

```bash
./log_analyzer.sh nieistniejacy.log ERROR
./log_analyzer.sh
```

**Output:**

```text
[ERROR] Plik nieistniejacy.log nie istnieje
[ERROR] Użycie: ./log_analyzer.sh <plik_logu> <wzorzec> [liczba_wynikow]
```

**Explanation:**

`validate_input()` checks for empty required parameters first (`-z`), then file existence (`-f`), returning `1` in either failure case so the main script can `exit 1` cleanly before touching `search_logs()` or `generate_report()`.

**Result:**  Homework 2 complete — filtering, counting, top-5 word report, and input validation all verified against a real test log.

