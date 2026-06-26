## Git Flow diagram (textual)

```
master    *-----------------------------*--------------*   (production, tags)
           \                       / (v1.0.0)        / (no-ff)
            \                     /                 /
release      \             *----* release/1.0.0   /
              \           /                       /
develop  *----*----*-----*-----------------------*----->  (integration)
          \    \   /       \                   (hotfix merged back to develop)
feature    \    * /         hotfix/critical-bug *
 monitoring  *  (logging)
```

Timeline (simplified):

1. `develop` is created from `master` and receives the initial commit.
2. Two `feature/*` branches branch off `develop`, each with a separate change.
3. Both `feature` branches are merged back into `develop` (monitoring fast-forward, logging `ort` merge).
4. `release/1.0.0` branches off `develop`, gets a version bump, then is merged into `master` with `--no-ff` + annotated tag `v1.0.0`.
5. `hotfix/critical-bug` branches off `master`, and after the fix is merged into both `master` (`--no-ff`) and `develop`.

## Procedures for each branch type

|Branch|Branches from|Merges back into|Purpose|
|---|---|---|---|
|`master`|—|—|stable production code, tagged releases|
|`develop`|`master`|—|current integration of the team's work|
|`feature/*`|`develop`|`develop`|development of a single feature|
|`release/*`|`develop`|`master` + `develop`|release stabilization, version bump|
|`hotfix/*`|`master`|`master` + `develop`|urgent production fix|

## Commands used in the task

```bash
# Initialization and develop
git init
git config user.name "Dev Student"
git config user.email "dev@learning.com"
git checkout -b develop
git add README.md && git commit -m "Initial commit on develop"

# Feature branches
git checkout -b feature/monitoring develop
git add monitoring.py && git commit -m "Add monitoring module"
git checkout -b feature/logging develop
git add README.md && git commit -m "Add logging documentation"

# Merging feature -> develop
git checkout develop
git merge feature/monitoring        # fast-forward
git merge feature/logging           # 'ort' merge

# Release + annotated tag
git checkout -b release/1.0.0 develop
git add VERSION && git commit -m "Release 1.0.0"
git branch master develop           # master created from develop
git checkout master
git merge --no-ff release/1.0.0 -m "Merge release/1.0.0"
git tag -a v1.0.0 -m "Version 1.0.0"

# Hotfix
git checkout -b hotfix/critical-bug master
git add bugfix.md && git commit -m "Critical security patch"
git checkout master
git merge --no-ff hotfix/critical-bug -m "Merge hotfix/critical-bug"
git checkout develop
git merge hotfix/critical-bug

# Advanced level: cleaning up history (squash)
git checkout -b experiment/rebase-demo
git config core.editor nano
git rebase -i HEAD~3                 # pick + squash + squash
```

## Explanation of conflicts and their resolution

In this task, merging `feature/monitoring` and `feature/logging` into `develop` did **not** trigger a conflict, even though both branches started from the same point:

- `feature/monitoring` added a new file `monitoring.py` (no collision with existing content),
- `feature/logging` appended a line to `README.md`.

Because the first merge was fast-forward (it advanced the develop pointer), the second merge concerned a different file/fragment — Git combined them automatically with the `ort` strategy. A conflict would require both branches to modify **the same fragment of the same file**. That scenario was deliberately produced and resolved in a separate task (see the report, Homework 3).

## Practical notes

- The repository's default branch is **`master`** (Git < 3.0), not `main` — all commands from the task referring to `main` were performed on `master`.
- `master` did not exist until it was explicitly created from `develop` (`git branch master develop`), because the first commit was made directly on `develop`.
- `git commit -am` skips **untracked** files (like the new `VERSION`); such files must be `git add`-ed first.
- Release tags were created as **annotated** (`git tag -a`), which include author, date and message — unlike lightweight tags.
