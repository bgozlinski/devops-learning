## Task 1 — Service status

*Use `systemctl` to check whether the cron service is active and permanently enabled.*

**Commands:**

```bash
systemctl is-active cron
systemctl is-enabled cron
systemctl status cron
```

**Output:**

```text
active
enabled
● cron.service - Regular background program processing daemon
     Loaded: loaded (/usr/lib/systemd/system/cron.service; enabled; preset: enabled)
     Active: active (running) since Tue 2026-06-02 15:32:32 UTC; 1min 33s ago
 Invocation: 8a180189312b4a8488063bb0b8d76e3f
       Docs: man:cron(8)
   Main PID: 1616 (cron)
      Tasks: 1 (limit: 7657)
     Memory: 520K (peak: 1.9M)
        CPU: 13ms
     CGroup: /system.slice/cron.service
             └─1616 /usr/sbin/cron -f -P
Jun 02 15:32:32 linux1 systemd[1]: Started cron.service - Regular background program processing daemon.
Jun 02 15:32:32 linux1 cron[1616]: (CRON) INFO (pidfile fd = 3)
```

**Explanation:**

The cron service is `active` (running) and `enabled` (it will start automatically at system boot). The `is-active` and `is-enabled` commands return a concise status, while `status` shows full information: the main process PID (1616), memory usage, the process tree (CGroup), and the most recent journal entries.

---

## Task 2 — Identifying a process

*Find the process identifier (PID) of the current shell session using `ps` combined with `grep`.*

**Commands:**

```bash
echo "PID mojej powłoki to: $$"
ps aux | grep $$ | grep -v grep
```

**Output:**

```text
bartek      3459  0.2  0.0  22020  7092 pts/0    Ss   15:32   0:00 -zsh
```

**Explanation:**

The special variable `$$` holds the PID of the current shell. Here it is **3459**, and the shell is `zsh`. The `grep -v grep` construct filters out the grep process itself so it does not appear in the results. In the STAT column, the value `Ss` means a sleeping process (`S`) that is a session leader (`s`) — typical for an interactive shell.

---

## Task 3 — Checking resources

*Display the amount of free space on the mounted partitions and the amount of free RAM in a human-readable format.*

**Commands:**

```bash
df -h
free -h
```

**Output:**

```text
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           1.7G  4.9M  1.7G   1% /run
/dev/sda2        30G  7.3G   21G  26% /
tmpfs           4.3G     0  4.3G   0% /dev/shm
tmpfs           4.3G  8.0K  4.3G   1% /tmp
tmpfs           861M   56K  861M   1% /run/user/60578
tmpfs           861M   48K  861M   1% /run/user/1000

               total        used        free      shared  buff/cache   available
Mem:           8.4Gi       871Mi       6.5Gi       7.3Mi       1.3Gi       7.6Gi
Swap:             0B          0B          0B
```

**Explanation:**

The main partition `/dev/sda2` is 30 GB, of which 26% (7.3 GB) is used, leaving **21 GB** free. The `tmpfs` entries are filesystems residing in RAM — they do not take up space on the physical disk.

The system has 8.4 GiB of RAM, of which **7.6 GiB** is actually available (the `available` column, which is more important than `free`, because it accounts for cache that is released back to applications on demand). There is no swap space configured (0 B) — typical for cloud virtual machines.

---

## Task 4 — Running in the background

*Start a counter command in the background, verify it is running with `ps`, and then terminate it with `kill`.*

**Commands:**

```bash
bash -c 'i=0; while true; do echo $i >> ~/licznik.log; i=$((i+1)); sleep 1; done' &
ps aux | grep licznik | grep -v grep
kill 5000
cat ~/licznik.log
```

**Output:**

```text
[1] 5000
bartek      5000  0.0  0.0  18820  4116 pts/0    SN   15:38   0:00 bash -c i=0; while true; do echo $i >> ~/licznik.log; ...
[1]  + 5000 terminated  bash -c
0
1
2
3
4
5
6
7
8
9
10
11
12
```

**Explanation:**

The `&` at the end of the command runs it in the background. The shell returned `[1] 5000` — the job number `[1]` and the process PID (5000). The `ps` command confirmed the process was running (state `SN` — sleeping, low priority). A plain `kill` (the SIGTERM signal) terminated it gracefully — there was no need to use `kill -9`. The `licznik.log` file contains the sequence of numbers from 0 to 12, corresponding to roughly 13 seconds of the counter running before it was stopped.

---

## Task 5 — Filtering logs

*Display all kernel messages from today that have a priority of warning or higher.*

**Commands:**

```bash
sudo journalctl -k --since today -p warning
```

**Output (excerpt):**

```text
Jun 02 15:32:25 linux1 kernel: APIC calibration not consistent with PM-Timer: 124ms instead of 100ms
Jun 02 15:32:25 linux1 kernel: mtrr: your CPUs had inconsistent variable MTRR settings
Jun 02 15:32:30 linux1 kernel: vmwgfx 0000:00:02.0: [drm] *ERROR* vmwgfx seems to be running on an unsupported hypervisor.
Jun 02 15:32:33 linux1 kernel: [UFW BLOCK] IN=enp0s3 ... SRC=192.168.1.104 DST=10.0.2.15 PROTO=UDP SPT=5353 DPT=5353
Jun 02 15:32:34 linux1 kernel: hrtimer: interrupt took 2907602 ns
Jun 02 15:32:50 linux1 kernel: clocksource: Long readout interval, skipping watchdog check
Jun 02 15:32:57 linux1 kernel: workqueue: blk_mq_run_work_fn hogged CPU for >10000us 4 times, consider switching to WQ_UNBOUND
[... excerpt; the full output contains repeating [UFW BLOCK] entries for multicast mDNS/WS-Discovery traffic ...]
```

**Explanation:**

The `-k` switch limits the output to kernel messages, `--since today` to the current day, and `-p warning` to warning priority and higher. The output opens in a pager; it can be closed with the `q` key or you can add `--no-pager`.

All the warnings are typical for a virtual machine and harmless: `vmwgfx` complains about an unsupported hypervisor, `[UFW BLOCK]` is the firewall correctly blocking multicast traffic (ports 5353/3702), and the `clocksource` and `hrtimer` messages stem from an uneven virtual clock.

---

# Challenge Tasks

## Task 6 — A custom systemd service

*Create a script that monitors system load, define a systemd unit file for it, then start and enable the service.*

**Commands:**

```bash
sudo tee /usr/local/bin/load-monitor.sh > /dev/null << 'EOF'
#!/bin/bash
while true; do
echo "$(date): $(uptime)" >> /var/log/system-load.log
sleep 10
done
EOF
sudo chmod +x /usr/local/bin/load-monitor.sh

sudo tee /etc/systemd/system/load-monitor.service > /dev/null << 'EOF'
[Unit]
Description=System Load Monitor
[Service]
ExecStart=/usr/local/bin/load-monitor.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start load-monitor
sudo systemctl enable load-monitor
sudo systemctl status load-monitor
cat /var/log/system-load.log
```

**Output:**

```text
Created symlink '/etc/systemd/system/multi-user.target.wants/load-monitor.service' → '/etc/systemd/system/load-monitor.service'.
● load-monitor.service - System Load Monitor
     Loaded: loaded (/etc/systemd/system/load-monitor.service; enabled; preset: enabled)
     Active: active (running) since Tue 2026-06-02 15:41:52 UTC; 10s ago
   Main PID: 5838 (load-monitor.sh)
      Tasks: 2 (limit: 7657)
     CGroup: /system.slice/load-monitor.service
             ├─5838 /bin/bash /usr/local/bin/load-monitor.sh
             └─6019 sleep 10

Tue Jun  2 03:41:52 PM UTC 2026:  15:41:52 up 9 min,  2 users,  load average: 0.20, 0.10, 0.04
Tue Jun  2 03:42:02 PM UTC 2026:  15:42:02 up 9 min,  2 users,  load average: 0.16, 0.09, 0.04
Tue Jun  2 03:42:12 PM UTC 2026:  15:42:12 up 9 min,  2 users,  load average: 0.14, 0.09, 0.04
Tue Jun  2 03:42:33 PM UTC 2026:  15:42:33 up 10 min, 2 users,  load average: 0.10, 0.08, 0.04
```

**Explanation:**

`daemon-reload` reloads the systemd configuration after a new unit file is added, `start` launches the service, and `enable` creates a link in `multi-user.target.wants/`, so that the service comes up automatically after a system restart. The status shows `active (running)` and Main PID 5838; the process tree also shows the `sleep 10` process (the script waiting between writes). The log confirms that every ~10 seconds a line with the date and the `uptime` result is appended, and the system load gradually decreases.

---

## Task 7 — Resource hunters

*Write a one-line command that displays the 5 processes consuming the most RAM, sorted in descending order.*

**Commands:**

```bash
ps aux --sort=-%mem | head -n 6
```

**Output:**

```text
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
gdm-gre+    2406  0.5  2.9 5965736 257332 ?      Ssl  15:32   0:03 /usr/bin/gnome-shell --mode=gdm
root        1919  0.4  0.9 2169664 86980 ?       Ssl  15:32   0:02 /usr/bin/dockerd -H fd:// --containerd=...
root        1856  0.2  0.5 1942108 50612 ?       Ssl  15:32   0:01 /usr/bin/containerd
root        5215  1.0  0.5 497748 46848 ?        Ssl  15:40   0:02 /usr/libexec/fwupd/fwupd
gdm-gre+    3032  0.0  0.5 772896 45760 ?        Ssl  15:32   0:00 /usr/libexec/xdg-desktop-portal-gnome
```

**Explanation:**

The `--sort=-%mem` option sorts processes in descending order by memory usage (the minus sign means descending order), and `head -n 6` displays the header plus the first 5 processes. The largest RAM consumer is `gnome-shell` (2.9%, ~257 MB), followed by `dockerd`, `containerd`, `fwupd`, and `xdg-desktop-portal-gnome`. The key column is **RSS** (the actual physical memory in KB); **VSZ** is virtual memory and can be misleadingly large. All values are healthy.

---

## Task 8 — Investigating the logs

*Find all sshd service logs from yesterday between 15:00 and 16:00 (scenario: a user reported an SSH login problem).*

**Commands:**

```bash
sudo journalctl -u ssh --since "$(date -d yesterday +%Y-%m-%d) 15:00:00" --until "$(date -d yesterday +%Y-%m-%d) 16:00:00"
```

**Output:**

```text
-- No entries --
```

**Explanation:**

The command is correct: `-u ssh` selects the SSH service unit (on Ubuntu the name is `ssh`, not `sshd`), and the substitution `$(date -d yesterday +%Y-%m-%d)` automatically inserts yesterday's date, so the `--since`/`--until` range covers 15:00–16:00 of the previous day.

The `-- No entries --` result means there are no entries in this range. This is expected, because the test machine was only started on the day the tasks were performed (uptime about 9 minutes), so no logs exist from the previous day. In a production environment with log history, the same command would return actual SSH service entries.

---

## Task 9 — An automatic guardian for the cron service

*Create a script that checks whether cron is running and restarts it if necessary. Test it manually: stop cron, run the script, and check the log.*

**Commands:**

```bash
sudo tee /usr/local/bin/cron-watcher.sh > /dev/null << 'EOF'
#!/bin/bash
if ! systemctl is-active --quiet cron; then
echo "$(date): cron nie działa, restartuję..." >> /var/log/cron-watcher.log
systemctl start cron
else
echo "$(date): cron działa prawidłowo" >> /var/log/cron-watcher.log
fi
EOF
sudo chmod +x /usr/local/bin/cron-watcher.sh

sudo systemctl stop cron
sudo /usr/local/bin/cron-watcher.sh
cat /var/log/cron-watcher.log
sudo systemctl status cron
```

**Output:**

```text
-rwxr-xr-x 1 root root 233 Jun  2 15:45 /usr/local/bin/cron-watcher.sh

Tue Jun  2 03:46:35 PM UTC 2026: cron nie działa, restartuję...

● cron.service - Regular background program processing daemon
     Active: active (running) since Tue 2026-06-02 15:46:35 UTC; 26s ago
   Main PID: 7009 (cron)
Jun 02 15:46:35 linux1 systemd[1]: Started cron.service - Regular background program processing daemon.
```

**Explanation:**

The script uses the condition `systemctl is-active --quiet cron` to check whether the service is running. If it is not, it appends an entry to the log and runs `systemctl start cron`; otherwise it logs that cron is working properly.

The proof of its effectiveness is the matching timestamps: the log entry is stamped `15:46:35`, and the cron status shows `Active since ... 15:46:35` as well as a new PID **7009** — the script restarted the service. This is the self-healing mechanism: detect the failure, log it, and fix it automatically.

---

## Task 10 — Automating monitoring (`.service` + `.timer`)

*Generate a `.service` file that runs the `cron-watcher.sh` script and a `.timer` file that invokes it every minute. Install them in the system, enable the timer, and verify it works.*

**Commands:**

```bash
sudo tee /etc/systemd/system/cron-watcher.service > /dev/null << 'EOF'
[Unit]
Description=Cron Watcher - sprawdza i restartuje usługę cron
[Service]
Type=oneshot
ExecStart=/usr/local/bin/cron-watcher.sh
EOF

sudo tee /etc/systemd/system/cron-watcher.timer > /dev/null << 'EOF'
[Unit]
Description=Uruchamia cron-watcher co minutę
[Timer]
OnCalendar=minutely
Persistent=true
[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now cron-watcher.timer
sudo systemctl list-timers cron-watcher.timer

# Verification: stop cron, wait a minute, check the log
sudo systemctl stop cron
sleep 65
sudo systemctl is-active cron
cat /var/log/cron-watcher.log
```

**Output:**

```text
Created symlink '/etc/systemd/system/timers.target.wants/cron-watcher.timer' → '/etc/systemd/system/cron-watcher.timer'.
NEXT                        LEFT LAST PASSED UNIT               ACTIVATES
Tue 2026-06-02 15:50:00 UTC  36s -         - cron-watcher.timer cron-watcher.service

active

Tue Jun  2 03:46:35 PM UTC 2026: cron nie działa, restartuję...
Tue Jun  2 03:50:09 PM UTC 2026: cron nie działa, restartuję...
Tue Jun  2 03:51:01 PM UTC 2026: cron działa prawidłowo
```

**Explanation:**

A `oneshot`-type service runs the script once and then exits, while the timer with `OnCalendar=minutely` triggers it every minute. `enable --now` both enables the timer permanently and starts it immediately; `list-timers` shows the scheduled next run.

The log documents the full automation cycle: the `15:46:35` entry comes from the manual test (Task 9), the `15:50:09` entry is the timer independently detecting and restarting cron (without user involvement), and `15:51:01` confirms that on the next invocation cron was already running. The `is-active` command returned `active`. The `.timer` + `.service` pair is a modern, fully systemd-integrated replacement for cron jobs.
