## Homework 1 — Automated backups with rsync

### Requirements covered

- `backup.sh` backs up configured directories, logs the process, and is driven by a config file.
- Limits retained backups to a maximum of 7 (rotation).
- `.service` + `.timer` units run it daily at midnight.
- A restore option recovers data from a chosen snapshot.

### Layout

```text
~/backup-system/
├── backup.conf        # configuration (sources, destination, retention)
├── backup.sh          # main backup + rotation script
├── restore.sh         # interactive restore
├── backups/           # timestamped snapshots: backup_YYYYMMDD_HHMMSS/
└── logs/              # per-run logs
```

### Configuration — `backup.conf`

```bash
SOURCE_DIRS="$HOME/Documents $HOME/Pictures"
BACKUP_ROOT="$HOME/backup-system/backups"
MAX_BACKUPS=7
```

### Main script — `backup.sh`

```bash
#!/bin/bash
# backup.sh — rsync-based backup with logging and rotation
set -u

CONFIG_FILE="$(dirname "$0")/backup.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config file not found: $CONFIG_FILE" >&2
    exit 1
fi
source "$CONFIG_FILE"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="$BACKUP_ROOT/backup_$TIMESTAMP"
LOG_DIR="$HOME/backup-system/logs"
mkdir -p "$LOG_DIR" "$BACKUP_ROOT"
LOG_FILE="$LOG_DIR/backup_$TIMESTAMP.log"

echo "=== Backup started at $(date) ===" | tee -a "$LOG_FILE"
mkdir -p "$DEST"

for dir in $SOURCE_DIRS; do
    if [ -d "$dir" ]; then
        echo "Backing up: $dir" | tee -a "$LOG_FILE"
        rsync -av "$dir" "$DEST/" >> "$LOG_FILE" 2>&1
    else
        echo "WARNING: source not found, skipping: $dir" | tee -a "$LOG_FILE"
    fi
done

echo "=== Backup finished at $(date) ===" | tee -a "$LOG_FILE"

# Rotation: keep only the newest $MAX_BACKUPS snapshots.
# Sort by NAME (timestamps sort lexically = chronologically), newest first.
echo "Rotating backups (keeping max $MAX_BACKUPS)..." | tee -a "$LOG_FILE"
cd "$BACKUP_ROOT" || exit 1
ls -1d backup_*/ 2>/dev/null | sort -r | tail -n +$((MAX_BACKUPS + 1)) | while read -r old; do
    echo "Removing old backup: $old" | tee -a "$LOG_FILE"
    rm -rf "$old"
done

echo "Current snapshots:" | tee -a "$LOG_FILE"
ls -1d "$BACKUP_ROOT"/backup_*/ 2>/dev/null | sort -r | tee -a "$LOG_FILE"
```

**Design note on rotation:** snapshots are sorted by **name**, not modification time. Because the directory names embed a `YYYYMMDD_HHMMSS` timestamp, lexical sort order equals chronological order. (An earlier version used `ls -t` by mtime, which mis-rotated when test directories shared a creation time — sorting by name is the robust fix.)

### First run

```text
=== Backup started at Mon Jun 15 04:57:53 PM UTC 2026 ===
Backing up: /home/bartek/Documents
Backing up: /home/bartek/Pictures
=== Backup finished at Mon Jun 15 04:57:53 PM UTC 2026 ===
Rotating backups (keeping max 7)...
Current snapshots:
/home/bartek/backup-system/backups/backup_20260615_165753/
```

Files confirmed copied:

```text
backup_20260615_165753/Documents/notes.txt
backup_20260615_165753/Documents/report.txt
backup_20260615_165753/Pictures/photo1.jpg
```

The log captured the full rsync verbose output (`sending incremental file list`, file names, byte counts) plus start/finish timestamps.

### Rotation test (max 7)

Eight backdated snapshots were created plus one real run (9 total). The script trimmed to exactly 7, removing the two oldest by name and **keeping the newest real snapshot**:

```text
Rotating backups (keeping max 7)...
Removing old backup: backup_20260602_120000/
Removing old backup: backup_20260601_120000/
Current snapshots:
/home/bartek/backup-system/backups/backup_20260615_170738/   <- newest real, kept
/home/bartek/backup-system/backups/backup_20260608_120000/
/home/bartek/backup-system/backups/backup_20260607_120000/
/home/bartek/backup-system/backups/backup_20260606_120000/
/home/bartek/backup-system/backups/backup_20260605_120000/
/home/bartek/backup-system/backups/backup_20260604_120000/
/home/bartek/backup-system/backups/backup_20260603_120000/
```

### Restore — `restore.sh`

```bash
#!/bin/bash
# restore.sh — restore files from a chosen backup snapshot
set -u

CONFIG_FILE="$(dirname "$0")/backup.conf"
source "$CONFIG_FILE"

echo "Available backup snapshots:"
mapfile -t SNAPS < <(ls -1d "$BACKUP_ROOT"/backup_*/ 2>/dev/null | sort -r)
if [ ${#SNAPS[@]} -eq 0 ]; then
    echo "No backups found in $BACKUP_ROOT"; exit 1
fi

i=1
for s in "${SNAPS[@]}"; do echo "  [$i] $(basename "$s")"; i=$((i+1)); done

read -rp "Enter the number of the snapshot to restore: " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#SNAPS[@]} ]; then
    echo "Invalid choice."; exit 1
fi

SELECTED="${SNAPS[$((choice-1))]}"
RESTORE_TARGET="$HOME/restored_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESTORE_TARGET"
echo "Restoring from: $SELECTED"
echo "Restoring into: $RESTORE_TARGET"
rsync -av "$SELECTED" "$RESTORE_TARGET/"
echo "Restore complete. Files are in: $RESTORE_TARGET"
```

**Restore run** (selected snapshot 1) recovered all three files into a fresh `~/restored_20260615_170850/` directory, restoring to a new location rather than overwriting the originals (safe default).

### systemd timer (daily at midnight)

`~/.config/systemd/user/backup.service`:

```ini
[Unit]
Description=Daily rsync backup of user directories

[Service]
Type=oneshot
ExecStart=%h/backup-system/backup.sh
```

`~/.config/systemd/user/backup.timer`:

```ini
[Unit]
Description=Run backup.sh daily at midnight

[Timer]
OnCalendar=*-*-* 00:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now backup.timer
```

**Timer scheduled** and **service verified** firing through systemd:

```text
NEXT                        LEFT LAST PASSED UNIT         ACTIVATES
Tue 2026-06-16 00:00:00 UTC   6h -         - backup.timer backup.service

# Manual trigger of the service:
Process: ExecStart=/home/bartek/backup-system/backup.sh (code=exited, status=0/SUCCESS)
TriggeredBy: ● backup.timer
```

`Type=oneshot` services correctly show `inactive (dead)` after a successful run. `Persistent=true` means a missed midnight run (VM powered off) executes at next boot.

---

## Homework 2 — Resource monitoring and alerting

### Requirements covered

- `monitor.sh` monitors CPU, memory, and disk usage.
- Checks availability of key network services.
- Scans the auth log for errors (failed root logins).
- Stores historical data for trend analysis.
- Alerts when: CPU > 80% for 5+ minutes, free disk < 10%, failed root logins occur, or a service is down.
- Runs on a systemd timer.

### Configuration — `monitor.conf`

```bash
CPU_THRESHOLD=80
CPU_SUSTAIN_MIN=5
DISK_MIN_FREE=10
SERVICES="127.0.0.1:22 1.1.1.1:443"
AUTH_LOG="/var/log/auth.log"
```

### Main script — `monitor.sh`

```bash
#!/bin/bash
# monitor.sh — system resource monitoring with alerting
set -u

CONFIG_FILE="$(dirname "$0")/monitor.conf"
source "$CONFIG_FILE"

BASE="$HOME/monitor-system"
HISTORY="$BASE/history.csv"
ALERTS="$BASE/alerts.log"
STATE="$BASE/cpu_state"   # tracks consecutive high-CPU minutes
NOW="$(date '+%Y-%m-%d %H:%M:%S')"

mkdir -p "$BASE"
[ -f "$HISTORY" ] || echo "timestamp,cpu_pct,mem_pct,disk_pct" > "$HISTORY"

alert() { echo "[$NOW] ALERT: $1" | tee -a "$ALERTS"; }

# CPU usage (100 - idle), sampled over 1s
CPU_IDLE=$(top -bn2 -d1 | grep -i "Cpu(s)" | tail -n1 | sed 's/.*, *\([0-9.]*\)%* id.*/\1/')
CPU_PCT=$(awk -v idle="$CPU_IDLE" 'BEGIN{printf "%.0f", 100 - idle}')

# Memory usage percent
MEM_PCT=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')

# Disk usage percent (root filesystem)
DISK_PCT=$(df --output=pcent / | tail -n1 | tr -dc '0-9')
DISK_FREE=$((100 - DISK_PCT))

# Store history
echo "$NOW,$CPU_PCT,$MEM_PCT,$DISK_PCT" >> "$HISTORY"
echo "[$NOW] CPU=${CPU_PCT}% MEM=${MEM_PCT}% DISK=${DISK_PCT}% (free ${DISK_FREE}%)"

# Alert: sustained high CPU
prev=0
[ -f "$STATE" ] && prev=$(cat "$STATE")
if [ "$CPU_PCT" -gt "$CPU_THRESHOLD" ]; then prev=$((prev + 1)); else prev=0; fi
echo "$prev" > "$STATE"
if [ "$prev" -ge "$CPU_SUSTAIN_MIN" ]; then
    alert "CPU above ${CPU_THRESHOLD}% for ${prev} consecutive minutes (now ${CPU_PCT}%)"
fi

# Alert: low disk space
if [ "$DISK_FREE" -lt "$DISK_MIN_FREE" ]; then
    alert "Free disk space below ${DISK_MIN_FREE}% (free ${DISK_FREE}%)"
fi

# Alert: failed root logins
if [ -r "$AUTH_LOG" ]; then
    ROOT_FAILS=$(grep "Failed password for root" "$AUTH_LOG" 2>/dev/null | wc -l)
    if [ "$ROOT_FAILS" -gt 0 ]; then
        alert "Found $ROOT_FAILS failed root login attempt(s) in $AUTH_LOG"
    fi
else
    echo "[$NOW] NOTE: cannot read $AUTH_LOG (need sudo); skipping root-login check"
fi

# Alert: service availability
for svc in $SERVICES; do
    host="${svc%%:*}"; port="${svc##*:}"
    if timeout 3 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        echo "[$NOW] service OK: $svc"
    else
        alert "Service unreachable: $svc"
    fi
done

echo "[$NOW] monitor run complete."
```

**Design note on sustained CPU:** the "5 minutes" requirement needs measurement _across_ runs, not a single sample. A state file (`cpu_state`) holds a counter that increments each minute CPU stays above 80% and resets to 0 the moment it drops. Combined with a per-minute timer, the alert fires only after 5 consecutive high readings — true sustained-load detection rather than reacting to a momentary spike.

### Normal run (healthy system, no alerts)

```text
[2026-06-15 17:13:13] CPU=20% MEM=32% DISK=28% (free 72%)
[2026-06-15 17:13:13] service OK: 127.0.0.1:22
[2026-06-15 17:13:13] service OK: 1.1.1.1:443
[2026-06-15 17:13:13] monitor run complete.
```

All metrics within thresholds, both services reachable (local SSH and outbound internet), so no alerts — correct behavior.

### History storage (trend data)

```text
timestamp,cpu_pct,mem_pct,disk_pct
2026-06-15 17:13:13,20,32,28
2026-06-15 17:15:03,22,32,28
2026-06-15 17:16:10,23,32,28
2026-06-15 17:17:10,27,32,28
2026-06-15 17:18:10,24,32,28
```

Each run appends one CSV row. The varying CPU column confirms live sampling.

### Alert verification

To prove the alert path, the disk threshold was temporarily set to require 90% free (only 72% available):

```text
[2026-06-15 17:15:03] CPU=22% MEM=32% DISK=28% (free 72%)
[2026-06-15 17:15:03] ALERT: Free disk space below 90% (free 72%)
...
# alerts.log:
[2026-06-15 17:15:03] ALERT: Free disk space below 90% (free 72%)
```

The alert printed to console **and** was persisted to `alerts.log`. The real 10% threshold was then restored.

### systemd timer (every minute)

`~/.config/systemd/user/monitor.timer`:

```ini
[Unit]
Description=Run monitor.sh every minute

[Timer]
OnCalendar=*-*-* *:*:00
Persistent=true

[Install]
WantedBy=timers.target
```

(with a matching `monitor.service` of `Type=oneshot` calling `%h/monitor-system/monitor.sh`).

**Verified firing automatically:** after enabling, `history.csv` grew by one row per minute with no manual runs, and the service reported:

```text
Process: ExecStart=/home/bartek/monitor-system/monitor.sh (code=exited, status=0/SUCCESS)
TriggeredBy: ● monitor.timer
```
