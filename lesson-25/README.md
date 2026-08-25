# Lesson 25 - Continuous Integration (part 1)

Homework 1: an advanced GitHub Actions workflow with conditional jobs.

| What | Where |
|---|---|
| Workflow | [`.github/workflows/lesson-25-ci.yml`](../.github/workflows/lesson-25-ci.yml) (repo root - GitHub only reads workflows from there) |
| Documentation | [WORKFLOW.md](WORKFLOW.md) |
| Application under CI | [`app/`](app) - `text_analyzer.py`, `address_book.py` (from lesson 23) |
| Tests | `app/test_text_analyzer.py`, `app/test_address_book.py` (11 tests) |
| Local run with Docker | [Dockerfile.ci](Dockerfile.ci) |

## Pipeline at a glance

```
build ──► test (3.11 / 3.12 / 3.13) ──► deploy (push to main only) ──► status (always)
```

- artifacts (build package + test reports) are uploaded **only for `main`**
- `deploy` runs **only** on a push to `main`, never on a pull request
- `status` runs with `if: always()` and reports the result of every job

## Run the checks locally

```bash
cd app
pip install pytest flake8
flake8 . --max-line-length=100
pytest -v
```

or with Docker (from this directory):

```bash
docker build -f Dockerfile.ci -t lesson25-ci .
docker run --rm lesson25-ci
```
