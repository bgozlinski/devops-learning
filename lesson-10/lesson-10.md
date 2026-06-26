## Homework 1 — Full Git-Flow cycle with conflicts

### Step 1 — Repository and the develop branch

**Commands:**

```bash
mkdir ~/devops_project && cd ~/devops_project
git init
git config user.name "Dev Student"
git config user.email "dev@learning.com"
git checkout -b develop
echo "# DevOps Project" > README.md
git add README.md
git commit -m "Initial commit on develop"
```

**Output:**

```text
Initialized empty Git repository in /home/bartek/devops_project/.git/
Switched to a new branch 'develop'
[develop (root-commit) c1d96e5] Initial commit on develop
 1 file changed, 1 insertion(+)
 create mode 100644 README.md
```

**Explanation:**

`git init` creates the `.git` directory. The identity was set locally (without `--global`), so it applies only to this repo. The `develop` branch was created right away and received the initial commit. Because the first commit landed on `develop`, the `master` branch does not exist at this stage.

### Step 2 — Two feature branches

**Commands:**

```bash
git checkout -b feature/monitoring develop
echo "monitoring_config = {}" > monitoring.py
git add monitoring.py && git commit -m "Add monitoring module"

git checkout develop
git checkout -b feature/logging develop
echo "## Logging" >> README.md
git add README.md && git commit -m "Add logging documentation"
```

**Output:**

```text
[feature/monitoring d9f684e] Add monitoring module
 1 file changed, 1 insertion(+)
 create mode 100644 monitoring.py

[feature/logging 943b76d] Add logging documentation
 1 file changed, 1 insertion(+)
```

**Explanation:**

Both `feature/*` branches branch off `develop`. `feature/monitoring` adds a new file, `feature/logging` appends a line to README — different files/fragments, so the merges will be conflict-free.

### Step 3 — Merging features into develop

**Commands:**

```bash
git checkout develop
git merge feature/monitoring
git merge feature/logging
git log --oneline --graph --all
```

**Output:**

```text
Updating c1d96e5..d9f684e
Fast-forward
 monitoring.py | 1 +

Merge made by the 'ort' strategy.
 README.md | 1 +

*   91c7ac0 (HEAD -> develop) Merge branch 'feature/logging' into develop
|\
| * 943b76d (feature/logging) Add logging documentation
* | d9f684e (feature/monitoring) Add monitoring module
|/
* c1d96e5 Initial commit on develop
```

**Explanation:**

The first merge (`feature/monitoring`) ran as a **fast-forward** — develop had no new commits of its own, so the pointer simply moved forward. The second merge (`feature/logging`) already required a merge commit (the `ort` strategy), because develop had been advanced earlier. The graph shows the branching and merging.

### Step 4 — Release, tag and hotfix

**Commands:**

```bash
git checkout -b release/1.0.0 develop
echo "1.0.0" > VERSION
git add VERSION
git commit -m "Release 1.0.0"

git branch master develop           # master created from develop
git checkout master
git merge --no-ff release/1.0.0 -m "Merge release/1.0.0"
git tag -a v1.0.0 -m "Version 1.0.0"

git checkout -b hotfix/critical-bug master
echo "# Bug fix" > bugfix.md
git add bugfix.md && git commit -m "Critical security patch"
git checkout master
git merge --no-ff hotfix/critical-bug -m "Merge hotfix/critical-bug"
git checkout develop
git merge hotfix/critical-bug
```

**Output:**

```text
[release/1.0.0 3941b2e] Release 1.0.0
 create mode 100644 VERSION

Merge made by the 'ort' strategy.   # release -> master (--no-ff)

[hotfix/critical-bug fe1b2d0] Critical security patch
 create mode 100644 bugfix.md

Merge made by the 'ort' strategy.   # hotfix -> master (--no-ff)

Updating 91c7ac0..fe1b2d0           # hotfix -> develop (fast-forward)
Fast-forward
 VERSION   | 1 +
 bugfix.md | 1 +
```

**Explanation:**

Two important things encountered in practice: (1) `master` had to be explicitly created from `develop` (`git branch master develop`), because it did not exist; (2) `git commit -am "Release 1.0.0"` skipped the `VERSION` file because it was **untracked** — `-a` only covers tracked files, so `git add VERSION` was required. Release and hotfix were merged with `--no-ff`, which forces a merge commit (preserving the branch information). The `v1.0.0` tag was created as **annotated** (`-a`). The hotfix was also merged back into `develop`, so the fix is not lost in future releases.

### Step 5 — Full Git Flow graph

**Command:**

```bash
git log --oneline --graph --all --decorate
```

**Output:**

```text
*   e939e03 (master) Merge hotfix/critical-bug
|\
| * fe1b2d0 (HEAD -> develop, hotfix/critical-bug) Critical security patch
|/
*   60da667 (tag: v1.0.0) Merge release/1.0.0
|\
| * 3941b2e (release/1.0.0) Release 1.0.0
|/
*   91c7ac0 Merge branch 'feature/logging' into develop
|\
| * 943b76d (feature/logging) Add logging documentation
* | d9f684e (feature/monitoring) Add monitoring module
|/
* c1d96e5 Initial commit on develop
```

**Explanation:**

The graph confirms the full Git Flow model: four branch types, two `--no-ff` merges (release and hotfix) as merge commits, the `v1.0.0` tag on the release commit, and the hotfix merged back into develop.

### Advanced level — interactive rebase (squash)

**Commands:**

```bash
git checkout -b experiment/rebase-demo
echo "wip 1" > scratch.txt && git add scratch.txt && git commit -m "wip: scratch 1"
echo "wip 2" >> scratch.txt && git add scratch.txt && git commit -m "wip: scratch 2"
echo "wip 3" >> scratch.txt && git add scratch.txt && git commit -m "wip: scratch 3"

git config core.editor nano
git rebase -i HEAD~3        # first line: pick, the rest: squash
# in the second editor: a single message "feat: add scratch feature"

git log --oneline -3
```

**Output:**

```text
833dcb6 (HEAD -> experiment/rebase-demo) feat: add scratch feature
fe1b2d0 (hotfix/critical-bug, develop) Critical security patch
60da667 (tag: v1.0.0) Merge release/1.0.0
```

**Explanation:**

Three "wip" commits were combined into one (`squash`) via interactive rebase, producing a clean history with a single `feat: add scratch feature` commit (the Conventional Commits convention). The operation was performed on a separate test branch so as not to rewrite the history of shared branches (`master`/`develop`).

> The **GIT_WORKFLOW.md** document (required by the task) is attached separately.

---

## Homework 2 — Remote collaboration: Push, Pull, PR

### Step 1 — Configuring SSH access to GitHub

**Commands:**

```bash
ssh -T git@github.com
ssh-keygen -t ed25519 -C "bgozlisnki@github" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub      # key added at github.com/settings/ssh/new
ssh -T git@github.com
```

**Output:**

```text
# before adding the key:
git@github.com: Permission denied (publickey).

# after adding the public key to GitHub:
Hi bgozlinski! You've successfully authenticated, but GitHub does not provide shell access.
```

**Explanation:**

The first `ssh -T` attempt returned `Permission denied`, because GitHub did not know any key. A new **ed25519** key was generated and its public part was added in the GitHub settings (Authentication Key). The greeting `Hi bgozlinski!` confirms correct authentication (and incidentally revealed the proper account name).

### Step 2 — Remote and branch push

**Commands:**

```bash
git remote add origin git@github.com:bgozlinski/devops_project.git
git push -u origin master
git push origin develop
git push origin v1.0.0
```

**Output:**

```text
To github.com:bgozlinski/devops_project.git
 * [new branch]      master -> master
 * [new branch]      develop -> develop
 * [new tag]         v1.0.0 -> v1.0.0
```

**Explanation:**

`git remote add origin` linked the local repo to the remote one. The `-u` on the first push sets up tracking (upstream). Both main branches and the release tag were pushed.

### Step 3 — Feature branch and colleague simulation

**Commands:**

```bash
# Developer 1 (you)
git checkout -b feature/api-docs
echo "API Documentation" > api.md
git add api.md && git commit -m "Add API documentation"
git push -u origin feature/api-docs

# Developer 2 (colleague) — separate clone with a different identity
git clone git@github.com:bgozlinski/devops_project.git ~/colleague_project
cd ~/colleague_project
git config user.name "Colleague Dev"
git config user.email "colleague@learning.com"
git checkout feature/api-docs
echo "Additional info" >> api.md
git add api.md && git commit -m "Enhance API docs"
git push origin feature/api-docs
```

**Output:**

```text
# You:
 * [new branch]      feature/api-docs -> feature/api-docs

# Colleague:
   effbeab..e7f9827  feature/api-docs -> feature/api-docs
```

**Explanation:**

The repository was cloned into a separate directory `~/colleague_project` with a different identity, simulating a second developer. Both worked on the same `feature/api-docs` branch; the colleague added a second commit and pushed it to the remote branch.

### Step 4 — Pulling the colleague's changes and the Pull Request

**Commands:**

```bash
cd ~/devops_project
git checkout feature/api-docs
git pull origin feature/api-docs
cat api.md
# Then in the browser: creating the PR feature/api-docs -> develop
```

**Output:**

```text
Updating effbeab..e7f9827
Fast-forward
 api.md | 1 +

# cat api.md:
API Documentation
Additional info

# PR created, merge possible:
https://github.com/bgozlinski/devops_project/pull/1
```

**Explanation:**

`git pull` pulled the colleague's commit (fast-forward) — `api.md` now contains both contributions. Pull Request #1 (`feature/api-docs` -> `develop`) was created in the GitHub interface, with a change description and the option to review.

### Step 5 — Merging the PR and cleanup

**Commands:**

```bash
# Merge the PR in the GitHub interface (Merge pull request -> Confirm)
git checkout develop
git pull origin develop
git branch -d feature/api-docs
git push origin --delete feature/api-docs
```

**Output:**

```text
Updating fe1b2d0..a5f2c8b
Fast-forward
 api.md | 2 ++

Deleted branch feature/api-docs (was e7f9827).
To github.com:bgozlinski/devops_project.git
 - [deleted]         feature/api-docs
```

**Explanation:**

After merging the PR on GitHub, the local `develop` was updated with `git pull` (api.md landed on develop). The feature branch was deleted locally (`-d` worked because it was already merged) and remotely (`--delete`), tidying up the repository.

> The **COLLABORATION.md** document (required by the task) is attached separately.

---

## Homework 3 — Resolving conflicts in Git

### Step 1 — Repository and base file

**Commands:**

```bash
mkdir ~/git-conflicts-lab && cd ~/git-conflicts-lab
git init
git config user.name "Dev Student"
git config user.email "dev@learning.com"
printf 'Linia 1: Witaj w projekcie\nLinia 2: To jest plik demonstracyjny\nLinia 3: Koniec pliku\n' > readme.txt
git add readme.txt
git commit -m "Początkowa wersja pliku"
```

**Output:**

```text
[master (root-commit) f66dc66] Początkowa wersja pliku
 1 file changed, 3 insertions(+)
 create mode 100644 readme.txt
```

**Explanation:**

The new repo had no identity (previous ones were set per-repo), hence the initial `Author identity unknown` error — fixed with `git config user.*`. The base file has three lines.

### Steps 2–3 — Divergent changes to the same line

**Commands:**

```bash
# branch-A changes line 2
git checkout -b branch-A
sed -i 's/.*plik demonstracyjny/Linia 2: Zmiana z branch-A - dodano logowanie/' readme.txt
git add readme.txt && git commit -m "branch-A: zmiana linii 2 - logowanie"

# master changes the SAME line 2
git checkout master
sed -i 's/.*plik demonstracyjny/Linia 2: Zmiana z main - dodano monitoring/' readme.txt
git add readme.txt && git commit -m "main: zmiana linii 2 - monitoring"
```

**Output:**

```text
[branch-A 591690b] branch-A: zmiana linii 2 - logowanie
 1 file changed, 1 insertion(+), 1 deletion(-)
[master ef8dd26] main: zmiana linii 2 - monitoring
 1 file changed, 1 insertion(+), 1 deletion(-)
```

**Explanation:**

Both branches modify **exactly the same line** of the same file, but in different ways — this is the classic scenario where Git cannot decide automatically.

### Step 4 — Conflict during merge

**Command:**

```bash
git merge branch-A
```

**Output:**

```text
Auto-merging readme.txt
CONFLICT (content): Merge conflict in readme.txt
Automatic merge failed; fix conflicts and then commit the result.
```

**Explanation:**

Git halted the merge and marked `readme.txt` as `both modified`, waiting for manual resolution.

### Step 5 — Conflict markers

**Command:**

```bash
cat readme.txt
```

**Output:**

```text
Linia 1: Witaj w projekcie
<<<<<<< HEAD
Linia 2: Zmiana z main - dodano monitoring
=======
Linia 2: Zmiana z branch-A - dodano logowanie
>>>>>>> branch-A
Linia 3: Koniec pliku
```

**Explanation:**

`<<<<<<< HEAD` begins the version from the current branch (`master`), `=======` is the separator, and `>>>>>>> branch-A` ends the version from the branch being merged. The task is to remove the markers and combine both changes.

### Step 6 — Resolving the conflict

**Commands:**

```bash
sed -i '/^<<<<<<< /,/^>>>>>>> /c\Linia 2: Dodano logowanie i monitoring' readme.txt
cat readme.txt
```

**Output:**

```text
Linia 1: Witaj w projekcie
Linia 2: Dodano logowanie i monitoring
Linia 3: Koniec pliku
```

**Explanation:**

The entire conflict block (from `<<<<<<<` to `>>>>>>>`) was replaced with a single line combining both intentions (logging + monitoring). The file no longer contains any markers.

### Steps 7–8 — Finishing the merge and verification

**Commands:**

```bash
git add readme.txt
git commit -m "Merge branch-A: połączono logowanie i monitoring"
git log --oneline --graph --all
cat readme.txt
```

**Output:**

```text
*   1819a93 (HEAD -> master) Merge branch-A: połączono logowanie i monitoring
|\
| * 591690b (branch-A) branch-A: zmiana linii 2 - logowanie
* | ef8dd26 main: zmiana linii 2 - monitoring
|/
* f66dc66 Początkowa wersja pliku

Linia 1: Witaj w projekcie
Linia 2: Dodano logowanie i monitoring
Linia 3: Koniec pliku
```

**Explanation:**

`git add` marked the conflict as resolved, and `git commit` finalized the merge commit. The graph shows two divergent branches converging in the merge commit `1819a93`, and `readme.txt` contains the correctly combined content.

---

## Summary

**Homework 1** completed a full Git Flow cycle: `develop`, two `feature` branches, a `release` with annotated tag `v1.0.0`, a `hotfix` merged into `master` and `develop`, and cleaning up history with an interactive rebase (`squash`) using the Conventional Commits convention.

**Homework 2** covered live remote collaboration via GitHub (SSH): key configuration, pushing branches and a tag, simulating a second developer through a separate clone, the full Pull Request cycle (#1) from push to merge, and branch cleanup locally and remotely.

**Homework 3** carried out a controlled merge conflict on the same line of a file and its manual resolution — from triggering the `CONFLICT`, through reading the markers, to combining the changes and finalizing the merge commit.

Attached documents: **GIT_WORKFLOW.md** (task 1) and **COLLABORATION.md** (task 2).
