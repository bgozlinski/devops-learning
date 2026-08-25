# Lesson 26 - Continuous Integration (part 2)

Homework 1: an advanced Jenkins pipeline with error handling and e-mail notifications.

| What | Where |
|---|---|
| Pipeline | [`Jenkinsfile`](Jenkinsfile) |
| Application under CI | [`app/cart.py`](app/cart.py) - shopping cart logic |
| Tests | [`app/test_cart.py`](app/test_cart.py) - 15 unit tests (pytest) |
| Jenkins for local runs | [`jenkins/`](jenkins) - `Dockerfile` + `docker-compose.yml` |

## Pipeline

```
Checkout --> Build --> Test --> Deploy
```

| Stage | What it does | Runs when |
|---|---|---|
| Checkout | `git url: ..., branch: ...` from the public repository; reads the author and message of the last commit for the notifications | always |
| Build | `python3 -m compileall` + `build/build-info.txt`, archived with `archiveArtifacts` | `CHECKOUT_RESULT == 'SUCCESS'` |
| Test | `pytest` with a JUnit report published in `post { always }` | `BUILD_RESULT == 'SUCCESS'` |
| Deploy | simulated deployment - copies the artifact to `deploy/` | `TEST_RESULT == 'SUCCESS'` **and** `DEPLOY_ENV == 'staging'` |

## Error handling

Every stage runs inside `script { try { ... } catch (Exception e) { ... } }` and writes its result
into an environment variable (`CHECKOUT_RESULT`, `BUILD_RESULT`, `TEST_RESULT`, `DEPLOY_RESULT`),
which the next stage reads in its `when {}` block. Not every failure is equally severe:

| Stage | Reaction to an error |
|---|---|
| Checkout | `currentBuild.result = 'FAILURE'` + `error()` - without the sources there is nothing to build |
| Build | `FAILURE` + `error()` - no artifact, so testing and deploying make no sense |
| Test | `UNSTABLE`, without `error()` - the pipeline finishes, but `TEST_RESULT` blocks the Deploy stage |
| Deploy | `FAILURE` + `error()` |

The `post` block of the pipeline publishes the test report, prints a summary of all four stages
(with the build result and duration) and sends the notifications:

| Block | Action |
|---|---|
| `always` | `junit` report + summary of the stage results |
| `success` | message in the console log |
| `unstable` | e-mail: tests failed, deployment skipped |
| `failure` | e-mail: pipeline failed |

## Notifications

The `notify(status, message)` function at the top of the `Jenkinsfile` prints the notification to
the console and sends it with the `mail` step. Every message contains the build result, the
execution time (`currentBuild.durationString`), the author and subject of the last commit, and the
build URL. The `mail` call itself is wrapped in `try/catch`, so a Jenkins instance without SMTP
configured logs a warning instead of failing the build.

E-mails are sent after a successful deployment (from the Deploy stage) and when the pipeline ends
as `FAILURE` or `UNSTABLE`.

## Environment variables

| Variable | Value | Used for |
|---|---|---|
| `APP_NAME` | `lesson-26-cart` | notifications, `build-info.txt` |
| `APP_VERSION` | `1.0.0` | version of the deployed application |
| `DEPLOY_ENV` | `staging` | condition of the Deploy stage (`environment name: 'DEPLOY_ENV', value: 'staging'`) |
| `GIT_REPO`, `GIT_BRANCH` | repository and branch | Checkout stage |
| `APP_DIR` | `lesson-26/app` | sources to compile and test |
| `NOTIFY_EMAIL` | address | notification recipient |

The stage results (`CHECKOUT_RESULT`, `BUILD_RESULT`, `TEST_RESULT`, `DEPLOY_RESULT`) are written at
runtime with `env.X = '...'` and deliberately **not** declared in `environment {}`: Jenkins re-applies
that block to every stage, which would overwrite the values set by the stages and leave every `when`
condition looking at the initial value.

## How to run

```bash
docker compose -f jenkins/docker-compose.yml up -d --build
docker exec lesson26-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Open <http://localhost:8080>, then **New Item -> Pipeline** and either paste the `Jenkinsfile` into
*Pipeline script*, or point *Pipeline script from SCM* at this repository with the script path
`lesson-26/Jenkinsfile`.

The image already contains `git`, `python3` and `pytest`, plus the plugins used by the pipeline
(Pipeline, Git, JUnit, Mailer). E-mails require **Manage Jenkins -> System -> E-mail Notification**
to be configured; without it the pipeline still runs and only logs the notification.

The Checkout stage clones `main`, so until this lesson is merged, set `GIT_BRANCH` in the
`environment {}` block to the working branch.

## Running the tests without Jenkins

```bash
cd app
pip install pytest
pytest -v
```
