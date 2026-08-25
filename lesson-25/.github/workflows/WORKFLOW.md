# Lesson 25 – GitHub Actions workflow: `lesson-25-ci.yml`

Workflow file: [`.github/workflows/lesson-25-ci.yml`](../.github/workflows/lesson-25-ci.yml) (GitHub only reads workflows from the repo-root `.github/workflows/`; a reference copy is kept in this folder as `lesson-25-ci.yml`)
Target project: [`lesson-25/app`](../lesson-25/app) (text analyzer + address book from lesson 23).

## Pipeline overview

```
push / pull_request
        │
        ├── build ──────────────┐
        │                       ├── deploy (main push only) ── status (always)
        └── test (3.11/3.12/3.13)┘
```

`build` and `test` run in parallel. `deploy` waits for both and only runs on a push to `main`.
`status` always runs last and summarises the whole pipeline.

## Triggers (`on:`)

| Event | Branches | Effect |
|---|---|---|
| `push` | `main`, `develop` | build + test; on `main` also artifact upload + deploy |
| `pull_request` | targeting `main` | build + test only (no artifact, no deploy) |

## Global environment variables (`env:`)

| Variable | Value | Used for |
|---|---|---|
| `APP_NAME` | `python-hw23` | artifact and tarball name |
| `APP_DIR` | `lesson-25/app` | path to the source code |
| `APP_VERSION` | `1.0.0` | base version, extended with the short commit SHA |
| `PYTHON_VERSION` | `3.12` | Python used in the build job |

## Jobs

### 1. `build`

| Step | What it does |
|---|---|
| Checkout | `actions/checkout@v4` – clones the repo |
| Set up Python | `actions/setup-python@v5` with `PYTHON_VERSION` |
| Compile sources | `python -m compileall` – fails on any syntax error (the Python equivalent of a compile step) |
| Determine version | builds `1.0.0-<short sha>` and exports it as a job **output** (`outputs.version`) so other jobs can use it |
| Package application | copies the `.py` files (without tests) to `dist/`, writes `BUILD_INFO`, creates `python-hw23-<version>.tar.gz` |
| Upload artifact | **`if: github.ref == 'refs/heads/main'`** – the tarball is stored as an artifact only for `main`, retention 30 days |

### 2. `test`

Runs as a **matrix** on Python 3.11, 3.12 and 3.13 (`fail-fast: false` so one failing version does not cancel the others).

| Step | What it does |
|---|---|
| Install test tools | `pip install pytest flake8` |
| Lint | `flake8` with max line length 100 |
| Run tests | `pytest -v` in `APP_DIR` (`test_text_analyzer.py`, `test_address_book.py`) |
| Report failure | **`if: failure()`** – emits a `::error::` annotation with the Python version |
| PR note | **`if: github.event_name == 'pull_request'`** – prints PR number and base branch |

### 3. `deploy`

```yaml
needs: [build, test]
if: github.event_name == 'push' && github.ref == 'refs/heads/main'
environment: production
```

Runs **only** on a push to `main` and only after `build` and `test` succeeded. A PR to `main` skips this job.

| Step | What it does |
|---|---|
| Download artifact | `actions/download-artifact@v4` – fetches the tarball uploaded by `build` |
| Inspect artifact | `ls` + `tar tzf` – proves the artifact is the one built in this run |
| Deploy (simulation) | prints app name, version (from `needs.build.outputs.version`), environment, timestamp |

### 4. `status`

```yaml
needs: [build, test, deploy]
if: always()
```

Runs even when earlier jobs failed or were skipped. Writes a Markdown table with the result of each job
to the **job summary** (`$GITHUB_STEP_SUMMARY`) and fails the pipeline if `build` or `test` did not succeed.
`deploy` being `skipped` (PR or `develop`) is fine and does not fail the status job.

## Conditions used (`if:`)

| Where | Condition | Purpose |
|---|---|---|
| build → Upload artifact | `github.ref == 'refs/heads/main'` | artifacts only for `main` |
| test → Report failure | `failure()` | runs only if a previous step failed |
| test → PR note | `github.event_name == 'pull_request'` | PR-only step |
| deploy (job) | `github.event_name == 'push' && github.ref == 'refs/heads/main'` | deploy only on push to `main` |
| status (job) | `always()` | always report |
| status → Fail if… | `needs.build.result != 'success' \|\| needs.test.result != 'success'` | propagate failure |

## Expected results

| Scenario | build | test | deploy | artifact |
|---|---|---|---|---|
| push to `main` | ✅ | ✅ | ✅ | ✅ |
| push to `develop` | ✅ | ✅ | skipped | ❌ |
| pull request → `main` | ✅ | ✅ | skipped | ❌ |

## Running locally with Docker (optional)

Same checks as the `test` job, without GitHub:

```bash
# from the repo root
docker build -f lesson-25/Dockerfile.ci -t hw23-ci .
docker run --rm hw23-ci
```

To test a different Python version:

```bash
docker build -f lesson-25/Dockerfile.ci --build-arg PY=3.11 -t hw23-ci:3.11 .
docker run --rm hw23-ci:3.11
```
