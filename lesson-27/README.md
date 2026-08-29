# Lesson 27 - Continuous Integration (part 3)

Jenkins agents: a permanent agent on a separate machine connected over SSH (homework 1) and
auto-scaled agents running in Docker containers (homework 2). The whole setup is written as code -
one `docker compose` run gives a controller that already has the node, the cloud, the credentials
and both test pipelines configured.

| What | Where |
|---|---|
| Controller image | [`jenkins/Dockerfile`](jenkins/Dockerfile) - Jenkins LTS + plugins |
| Agent "virtual machine" | [`jenkins/agent.Dockerfile`](jenkins/agent.Dockerfile) - Ubuntu 22.04 + sshd + JRE 21 |
| Docker cloud agent image | [`jenkins/docker-agent.Dockerfile`](jenkins/docker-agent.Dockerfile) - inbound agent + git/python3 |
| Lab stack | [`jenkins/docker-compose.yml`](jenkins/docker-compose.yml) |
| Configuration as code | [`jenkins/casc/jenkins.yaml`](jenkins/casc/jenkins.yaml), [`jenkins/casc/jobs.groovy`](jenkins/casc/jobs.groovy) |
| Homework 1 pipeline | [`pipelines/Jenkinsfile.static-agent`](pipelines/Jenkinsfile.static-agent) |
| Homework 2 pipeline | [`pipelines/Jenkinsfile.docker-agent`](pipelines/Jenkinsfile.docker-agent) |
| Setup script for a real VM | [`scripts/setup-agent-vm.sh`](scripts/setup-agent-vm.sh) |

## How to run

```bash
cd lesson-27
docker compose -f jenkins/docker-compose.yml --profile build-only build
docker compose -f jenkins/docker-compose.yml up -d
```

Open <http://localhost:8080> and log in as **admin / admin123**. Two jobs are already there:
`lesson-27-static-agent` and `lesson-27-docker-agent`. Run them - nothing else has to be clicked.

The `--profile build-only` part builds the image used by the Docker cloud. That service is never
started by Compose; Jenkins creates containers from the image on demand.

```
                        +---------------------------+
                        |  lesson27-jenkins         |
                        |  controller, 0 executors  |
                        +------+-------------+------+
                    SSH (out)  |             |  Docker API (/var/run/docker.sock)
             +-----------------+             +------------------+
             |                                                  |
 +-----------v------------+                    +----------------v-----------------+
 | linux-worker-01        |                    | docker-agent-template            |
 | permanent, 2 executors |                    | on demand, max 2 containers,     |
 | NODE_ENV=production    |                    | container removed after a build  |
 +------------------------+                    +----------------------------------+
```

## Homework 1 - permanent agent on a separate machine

The node is defined in `jenkins/casc/jenkins.yaml` (`jenkins.nodes[].permanent`):

| Setting | Value | Why |
|---|---|---|
| Name | `linux-worker-01` | |
| Labels | `linux-worker-01 linux ubuntu` | the pipeline picks the node with `agent { label 'linux-worker-01' }` |
| Remote root directory | `/home/jenkins/agent` | workspace on the agent machine |
| Executors | 2 | two builds can run on this node at once |
| Launch method | Launch agents via SSH | the controller opens the connection, the agent needs no access back to Jenkins |
| Credentials | `jenkins / jenkins123` (username + password) | account created on the agent machine |
| Host key verification | non-verifying | lab only - the image is rebuilt, so its host key changes |
| Node properties | `NODE_ENV=production`, `AGENT_ROLE=linux-worker` | node environment variables, inherited by every build |

The agent machine ([`jenkins/agent.Dockerfile`](jenkins/agent.Dockerfile)) is a plain Ubuntu 22.04
with `openssh-server`, `openjdk-21-jre-headless` (the same Java major version as the controller)
and a `jenkins` user - exactly what [`scripts/setup-agent-vm.sh`](scripts/setup-agent-vm.sh) does
on a real VirtualBox / VMware / VPS machine.

`pipelines/Jenkinsfile.static-agent` covers all three requirements of the task:

| Stage | Checks |
|---|---|
| Agent identity | `hostname`, `whoami`, `pwd`, `java -version`; fails if the build landed on the controller |
| System check | `uname -a`, `free -m`, `df -h /`, `nproc`, `/etc/os-release` |
| Verify NODE_ENV | reads `NODE_ENV` from Groovy **and** from the shell, fails when it is not `production` |
| Workspace smoke test | writes and archives `build/agent-info.txt` |

`NODE_ENV` is deliberately not set anywhere in the `Jenkinsfile`; if that stage passes, the value
can only come from the node configuration.

Output of a run:

```
Running on linux-worker-01 in /home/jenkins/agent/workspace/lesson-27-static-agent
+ hostname            -> linux-worker-01
+ whoami              -> jenkins
+ java -version       -> openjdk version "21.0.12" (Ubuntu 22.04)
+ uname -a            -> Linux linux-worker-01 ... x86_64 GNU/Linux
NODE_ENV seen by Groovy: production
NODE_ENV seen by sh    : production
Finished: SUCCESS
```

## Homework 2 - auto-scaled Docker agents

The cloud is defined in the same file (`jenkins.clouds[].docker`):

| Setting | Value |
|---|---|
| Docker host URI | `unix:///var/run/docker.sock` - the host daemon, mounted into the controller |
| Template labels | `docker-agent` |
| Image | `lesson27-docker-agent:jdk21` |
| Instance capacity | 2 |
| Pull strategy | `PULL_NEVER` - the image is built locally, so it must not be looked up in a registry |
| Network | `lesson27-net` - the same network the controller runs in |
| Connect method | inbound agent (JNLP), user `jenkins`, controller URL `http://jenkins:8080/` |
| Retention | `DockerOnceRetentionStrategy` - one build per container, then the container is removed |

`pipelines/Jenkinsfile.docker-agent` uses `agent none` at the top and asks for a node per stage:

| Stage | What it shows |
|---|---|
| Container info | `cat /etc/os-release`, `hostname`, `whoami`, `java -version`, `uname -a`, `nproc`, `free -m` |
| Auto-scaling | two parallel stages request `docker-agent` at the same time, so the cloud has to start two containers |
| Ephemeral workspace | the workspace is always empty - every build gets a fresh container |

Output of a run:

```
Running on docker-agent-template-00000owo0lmav on docker
+ cat /etc/os-release  -> PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
+ whoami               -> jenkins
+ java -version        -> openjdk version "21.0.12.1" (Temurin)
worker A na ba6ad489cd9a      <- two containers at the same time
worker B na 39e85220d26f
workspace jest czysty
Finished: SUCCESS
```

`docker ps` during the parallel stage lists both agent containers; shortly after the build they are
gone.

### Why the inbound connector instead of SSH for the Docker cloud

The Docker plugin can also connect to its containers over SSH, but that path does not work when the
controller itself runs in a container. Both failures are worth knowing:

1. **`sshd: no hostkeys available -- exiting`** - with "inject SSH key" the plugin overrides the
   container command with `/usr/sbin/sshd -D -p 22 -o AuthorizedKeysCommand=...`. That bypasses the
   entrypoint of `jenkins/ssh-agent`, which is what normally runs `ssh-keygen -A`, so sshd exits
   with status 1 right away. Generating host keys during the image build fixes this one.
2. **Unreachable published port** - the plugin then publishes container port 22 on a random host
   port and connects to `localhost:<port>`. Inside the controller container `localhost` is the
   controller itself, so the attempt ends with
   `SSH service hadn't started after 60 seconds`.

The inbound connector reverses the direction: the container connects out to `http://jenkins:8080/`
and to agent port 50000 (`jenkins.slaveAgentPort` in the JCasC file). That works because the agent
containers are started in `lesson27-net`, the same network as the controller.

## Configuration as code

Nothing in this lab is clicked in the UI. `CASC_JENKINS_CONFIG` points at
`jenkins/casc/jenkins.yaml`, which holds the security realm, the permanent node, the Docker cloud,
the credentials and the seed jobs. `jenkins/casc/jobs.groovy` (Job DSL) creates both pipeline jobs
from the files in `pipelines/`, mounted read-only under `/var/jenkins_pipelines`.

Two details that are easy to get wrong:

- `name: lesson-27` at the top of the Compose file. Without it Compose takes the project name from
  the directory holding the Compose file (`jenkins`), and the lab silently reuses the volume of the
  lesson 26 lab - the controller then starts with the old jobs and the old admin user.
- `./casc` is mounted read-only, so nothing can be mounted *inside* it. The pipelines therefore go
  to `/var/jenkins_pipelines` instead of a subdirectory of `/var/jenkins_config`.

After editing a `Jenkinsfile` or the JCasC file, reload the configuration:

```bash
docker restart lesson27-jenkins
# or: Manage Jenkins -> Configuration as Code -> Reload existing configuration
```

## Security notes

What this lab does for convenience, and what production would do instead:

| Lab | Production |
|---|---|
| password credentials for the SSH agent | SSH key pair, `PasswordAuthentication no` on the agent |
| `nonVerifyingKeyVerificationStrategy` | known hosts / manually trusted key |
| `/var/run/docker.sock` mounted into the controller (root access to the host daemon) | separate Docker host over TCP + TLS certificates |
| controller container runs as `root` (needed for the socket) | unprivileged user, no socket |
| admin password in `docker-compose.yml` | secret from a file or a secret manager |

The controller follows the practice from the lesson: `numExecutors: 0` and `mode: EXCLUSIVE`, so no
build can ever run on it.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `linux-worker-01` offline | agent machine down or Java missing - `docker logs lesson27-linux-worker-01`, then the node log in Jenkins |
| `All nodes of label 'docker-agent' are offline` | provisioning failed; after a failure the template is disabled for 5 minutes - read `docker logs lesson27-jenkins` |
| `Failed to launch docker SSH agent. Container exited with status 1` | the SSH connect method - see the section above, use the inbound connector |
| `no such image` while provisioning | the agent image was not built - run the `--profile build-only build` command |
| jobs from lesson 26 show up | old volume reused - `docker compose -f jenkins/docker-compose.yml down -v`, then start again |

## Clean up

```bash
docker compose -f jenkins/docker-compose.yml down -v
```
