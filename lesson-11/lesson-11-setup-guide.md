
Guide for using `project_setup.sh` — an extended version of the project scaffolding script from Lesson 11, with positional arguments, language-specific `.gitignore`, a starter source file, and action logging.

## Usage

```bash
./project_setup.sh <project_name> <language> [directories]
./project_setup.sh --help
```

## Parameters

|Parameter|Required|Description|
|---|---|---|
|`$1` — `project_name`|Yes|Name of the project / root directory to create|
|`$2` — `language`|Yes|One of: `python`, `js`, `go`. Controls `.gitignore` content and the starter file created|
|`$3` — `directories`|No|Comma-separated list of subdirectories to create. Defaults to `src,tests,docs`|
|`--help`|No|Prints usage information and exits|

## What the script does

1. Validates arguments (`$#`, `--help`, allowed language list)
2. Creates the root project directory (`create_dir()`)
3. Creates all requested subdirectories from the CSV list (`$3` split via `IFS=','`)
4. Generates a language-specific `.gitignore` (`create_gitignore()`)
5. Generates a starter source file — `main.py`, `index.js`, or `main.go` (`create_main_file()`)
6. Initializes a local Git repository if `git` is available
7. Logs every action with a timestamp to `<project_name>/setup.log` (`log_action()`)

## Examples

Create a Python project with default directories:

```bash
./project_setup.sh myapp python
```

Create a JS project with custom directories:

```bash
./project_setup.sh webapp js "src,tests,build,public"
```

Create a Go project:

```bash
./project_setup.sh api-service go "src,tests,config"
```

Show help:

```bash
./project_setup.sh --help
```

## Error handling

- Running with fewer than 2 arguments prints usage and exits with code `1`.
- An unsupported language (anything outside `python|js|go`) is rejected before any directory is created.
- If the root project directory already exists, the script warns and stops (`create_dir()` returns `1`), preventing accidental overwrites.