# Lesson 24 – Homework: Python OOP & Scripting (Library System + Service Monitor)

## Homework 1: Library Management System (`library.py`)

### Class design

| Class | Responsibility | Key attributes |
|-------|----------------|----------------|
| `Ksiazka` | one book | title, author, ISBN, year, `dostepna` flag |
| `Czytelnik` | one reader | name, reader number, `__wypozyczone` (private list of borrowed books) |
| `Biblioteka` | the system | name, address, `__ksiazki`, `__czytelnicy` (private collections) + all operations |

`Biblioteka` provides: adding/removing books, registering readers, borrowing (`wypozycz`), returning (`zwroc`), searching by title/author/ISBN (`szukaj`, case-insensitive substring), and per-reader status (`stan_czytelnika`).

### Encapsulation

- The book collection, reader list, and each reader's borrowed list use double-underscore names (`__ksiazki`, `__czytelnicy`, `__wypozyczone`) — Python name mangling blocks accidental outside access; all mutations go through methods.
- `Czytelnik.lista_wypozyczonych()` returns a **copy** of the private list, so callers can read it but cannot mutate the reader's internal state.
- Direct access is demonstrated to fail in the test block:

```python
try:
    print(bib.__ksiazki)
except AttributeError as e:
    print(f"Blad przy bezposrednim dostepie: {e}")
# -> 'Biblioteka' object has no attribute '__ksiazki'
```

### State consistency rules

- Borrowing an unavailable book is refused (`'Hobbit' jest juz wypozyczona.`).
- Returning a book the reader doesn't have is refused.
- **A borrowed book cannot be removed from the collection** — deletion is only allowed when `dostepna` is true, which keeps reader records and the collection consistent.

### Test run (built into `__main__`)

The test walks through every required operation on sample data — 3 books, 2 readers:

```
=== Wypozyczenia ===
Jan Kowalski wypozyczyl(a) 'Hobbit'.
'Hobbit' jest juz wypozyczona.          # borrow conflict rejected
Anna Nowak wypozyczyl(a) 'Wiedzmin'.

=== Zwrot i usuwanie ===
Nie mozna usunac - ksiazka nie istnieje lub jest wypozyczona.   # delete refused
Jan Kowalski zwrocil(a) 'Hobbit'.
Usunieto ksiazke ISBN 978-0261102217.                           # delete OK after return

=== Enkapsulacja ===
Blad przy bezposrednim dostepie: 'Biblioteka' object has no attribute '__ksiazki'
```

All scenarios behaved as expected, including the failure paths.

## Homework 2: Service & Weather Monitor (`service_monitor.py`)

### What it does

1. Sends GET requests to a list of URLs (`https://api.github.com`, `https://google.com`, plus `https://httpstat.us/503` added deliberately to demonstrate the DOWN path).
2. Fetches current weather for Dublin as JSON from `https://wttr.in/Dublin?format=j1`.
3. Writes a combined report to `daily_report.yaml` with `services_status` and `environment_info` sections.

### Design decisions

- **UP/DOWN rule** – any response with status code `< 400` counts as 🟢 UP; codes `>= 400` and request exceptions (timeout, DNS, connection errors) count as 🔴 DOWN, with the code or exception name included for debugging.
- **Timeouts everywhere** – `timeout=5` for service checks, `timeout=10` for the weather API; a monitoring script must never hang on a dead endpoint.
- **Defensive weather parsing** – `raise_for_status()` plus a `try/except` over `RequestException`, `KeyError` and `ValueError`; on failure the report still gets an `environment_info` section with an `error` field instead of crashing.
- **YAML output** – `yaml.dump(..., allow_unicode=True, sort_keys=False)`: unicode keeps the emoji readable in the file, `sort_keys=False` preserves the logical section order.

### Generated report

```yaml
generated_at: '2026-08-11T18:32:41'
services_status:
  https://api.github.com: 🟢 UP (200)
  https://google.com: 🟢 UP (200)
  https://httpstat.us/503: 🔴 DOWN (ConnectionError)
environment_info:
  region: Dublin
  temperature_c: 24
  feels_like_c: 25
  description: Sunny
```

Note: the test endpoint reported `ConnectionError` rather than the expected HTTP 503 — the httpstat.us service itself was unreachable at the time. Either way it exercised the DOWN path, just via the exception branch instead of the status-code branch.

## Conclusions

- Name mangling (`__attr`) is Python's lightweight encapsulation: it prevents accidents, not determined access — good enough to force all mutations through methods that enforce invariants (like "no deleting borrowed books").
- Returning copies of internal lists is a simple, effective way to expose state read-only.
- For monitoring scripts, the failure paths are the product: timeouts, exception handling and degraded-but-valid output matter more than the happy path.
- `requests` + `yaml.dump` is a minimal, idiomatic stack for the classic DevOps pattern "probe things, emit a machine-readable report".