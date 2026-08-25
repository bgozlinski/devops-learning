# Lesson 25 - GitHub Actions workflow explained

Workflow file: [`.github/workflows/lesson-25-ci.yml`](../.github/workflows/lesson-25-ci.yml)
(in the **repository root** - GitHub Actions only discovers workflows in `<repo>/.github/workflows/`).

The pipeline builds, tests, deploys and reports on the small Python application in `lesson-25/app/`.

```
build --> test (matrix 3.11 / 3.12 / 3.13) --> deploy (main only) --> status (always)
```

---

## 1. Triggers (`on:`)

```yaml
on:
  push:
    branches: [ main, develop, 'lesson-25/**' ]
    paths: [ 'lesson-25/**', '.github/workflows/lesson-25-ci.yml' ]
  pull_request:
    branches: [ main ]
    paths: [ 'lesson-25/**', '.github/workflows/lesson-25-ci.yml' ]
```

| Element | Meaning |
|---|---|
| `push` | runs on every push to `main`, `develop` and any `lesson-25/*` branch |
| `pull_request` | runs on every PR **targeting `main`** |
| `paths` | the repository holds many lessons - the workflow only starts when files of this lesson (or the workflow itself) change |

## 2. Global settings

```yaml
permissions:
  contents: read              # least privilege - the pipeline only reads the repo

concurrency:
  group: lesson-25-${{ github.ref }}
  cancel-in-progress: true    # a new push cancels the still-running old run on the same branch

defaults:
  run:
    shell: bash               # one shell for every run step
```

## 3. Environment variables (`env:`)

Declared once at workflow level, visible in every job and step as `$NAME` (shell) or `${{ env.NAME }}` (expression).

| Variable | Value | Purpose |
|---|---|---|
| `APP_NAME` | `lesson25-app` | artifact / package name |
| `APP_DIR` | `lesson-25/app` | path to the source code |
| `APP_VERSION` | `1.0.0` | base version, extended with the short commit SHA |
| `PYTHON_VERSION` | `3.12` | Python used by the build job |

---

## Jobs

### Job 1 - `build`

Prepares and packages the application; exposes two **job outputs** consumed by later jobs.

| Step | What it does |
|---|---|
| Checkout | `actions/checkout@v4` - clones the repository |
| Set up Python | `actions/setup-python@v5` with `${{ env.PYTHON_VERSION }}` |
| Compile sources | `python -m compileall -q "$APP_DIR"` - fails on any syntax error (the Python equivalent of a compile step) |
| Determine version | builds `1.0.0-<short sha>` and sets `is_main=true/false`; both are written to `$GITHUB_OUTPUT` so other jobs can read them via `needs.build.outputs.*` |
| Package application | copies the `.py` files (tests excluded) into `dist/`, writes a `BUILD_INFO` file (app, version, commit, branch, build time) and creates `lesson25-app-<version>.tar.gz` |
| Upload build artifact | **`if: steps.version.outputs.is_main == 'true'`** - the tarball is stored as a downloadable artifact **only for `main`** (retention 30 days, `if-no-files-found: error`) |
| Note - artifact skipped | **`if: ... != 'true'`** - on other branches it prints a `::notice::` instead of uploading |

### Job 2 - `test`

```yaml
needs: build
strategy:
  fail-fast: false
  matrix:
    python-version: ["3.11", "3.12", "3.13"]
```

Runs as a **matrix** of three parallel jobs. `fail-fast: false` means a failure on one Python version does not
cancel the other two, so you see the full picture. `needs: build` also gives access to
`needs.build.outputs.is_main`.

| Step | What it does |
|---|---|
| Install test tools | `pip install pytest flake8` |
| Lint | `flake8 "$APP_DIR" --max-line-length=100` |
| Run tests | `pytest -v --junitxml=...` in `APP_DIR` (11 tests in `test_text_analyzer.py` + `test_address_book.py`) |
| Upload test report | **`if: always() && needs.build.outputs.is_main == 'true'`** - the JUnit XML is uploaded **only for `main`**; `always()` keeps the report even when tests fail |
| Report failure | **`if: failure()`** - emits a `::error::` annotation naming the Python version |
| Pull request note | **`if: github.event_name == 'pull_request'`** - prints the PR number and base branch, and states that deploy is skipped |

### Job 3 - `deploy`

```yaml
needs: [build, test]
if: github.event_name == 'push' && github.ref == 'refs/heads/main'
environment: production
```

Two conditions guard it: the event must be a **push** (so a PR to `main` never deploys) **and** the ref must be
`refs/heads/main`. `needs` makes it wait for `build` **and** all three matrix `test` jobs - if any of them fails,
deploy never starts. `environment: production` groups the deployment under the GitHub *Environments* tab and
allows adding required reviewers or secrets later.

| Step | What it does |
|---|---|
| Download build artifact | `actions/download-artifact@v4` - fetches the tarball produced by `build` |
| Inspect artifact | `tar tzf` + prints `BUILD_INFO` - proves the deployed package is the one built in this very run |
| Deploy (simulation) | prints app, version (`needs.build.outputs.version`), environment, timestamp, status |
| Deployment summary | appends the deployed version and commit to `$GITHUB_STEP_SUMMARY` |

### Job 4 - `status`

```yaml
needs: [build, test, deploy]
if: always()
```

`always()` makes this job run even when a previous job failed **or was skipped** - without it the whole job would
be skipped together with `deploy`.

| Step | What it does |
|---|---|
| Pipeline summary | writes a Markdown table with `needs.<job>.result` for build / test / deploy into the run's **Summary** page |
| Deploy skipped explanation | **`if: needs.deploy.result == 'skipped'`** - explains that deploy only runs on push to `main` |
| Fail if build or test failed | **`if: needs.build.result != 'success' \|\| needs.test.result != 'success'`** - `exit 1` so the whole run is marked red; a *skipped* deploy on a PR is fine and does **not** fail the run |

---

## All conditions used (`if:`)

| Where | Condition | Purpose |
|---|---|---|
| build / Upload build artifact | `steps.version.outputs.is_main == 'true'` | artifacts only for `main` |
| build / Note - artifact skipped | `steps.version.outputs.is_main != 'true'` | explain why nothing was uploaded |
| test / Upload test report | `always() && needs.build.outputs.is_main == 'true'` | reports only for `main`, also when tests fail |
| test / Report failure | `failure()` | runs only after a failed step |
| test / Pull request note | `github.event_name == 'pull_request'` | PR-only step |
| deploy (job) | `github.event_name == 'push' && github.ref == 'refs/heads/main'` | **deploy only on push to `main`** |
| status (job) | `always()` | report regardless of previous results |
| status / Deploy skipped | `needs.deploy.result == 'skipped'` | informational notice |
| status / Fail if build or test failed | `needs.build.result != 'success' \|\| needs.test.result != 'success'` | propagate failure to the run |

## Expected behaviour

| Scenario | build | test | deploy | status | artifacts |
|---|---|---|---|---|---|
| push to `main` | PASSED | PASSED | PASSED | PASSED | build package + 3 test reports |
| push to `develop` / `lesson-25/*` | PASSED | PASSED | skipped | PASSED | none |
| pull request to `main` | PASSED | PASSED | skipped | PASSED | none |
| failing test | PASSED | FAILED | skipped | FAILED | test reports (main only) |

In the **Actions** tab of a successful run on `main`:

```
[PASSED] Build                          (~20s)
[PASSED] Test (Python 3.11/3.12/3.13)   (~30s each, in parallel)
[PASSED] Deploy to prod                 (~10s)   <- only on main
[PASSED] Status report                  (~5s)
```

Artifacts (`lesson25-app-build`, `test-report-py3.11/3.12/3.13`) are downloadable from the
**Artifacts** section at the bottom of the run page.

---

## Running the checks locally with Docker (optional)

The same lint + test steps as the `test` job, without GitHub. Run from the `lesson-25/` directory:

```bash
docker build -f Dockerfile.ci -t lesson25-ci .
docker run --rm lesson25-ci
```

A different Python version (matches one leg of the CI matrix):

```bash
docker build -f Dockerfile.ci --build-arg PY=3.11 -t lesson25-ci:3.11 .
docker run --rm lesson25-ci:3.11
```

Without Docker:

```bash
cd app
pip install pytest flake8
flake8 . --max-line-length=100
pytest -v
```
