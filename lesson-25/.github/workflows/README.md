# Lesson 25 – Continuous Integration (part 1)

Homework 1: advanced GitHub Actions workflow with conditional jobs.

```
lesson-25/
├── app/                 # code under test (copy of lesson-23 python-hw23) + pytest tests
├── lesson-25-ci.yml     # reference copy of the workflow
├── WORKFLOW.md          # step-by-step explanation of the pipeline
├── Dockerfile.ci        # run lint + tests locally in Docker
└── README.md
```

The active workflow lives in `.github/workflows/lesson-25-ci.yml` (repo root) – that is the only
location GitHub Actions scans.
