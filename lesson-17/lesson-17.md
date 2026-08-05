# Lesson 17 — Databases Part 2: Fault Tolerance & High Availability


## Homework 1: Backup Strategy for a Critical PostgreSQL Database

### 1. Needs Analysis

| Parameter | Value | Rationale |
|---|---|---|
| RPO (Recovery Point Objective) | ≤ 16 MB of WAL (seconds–minutes) | Continuous WAL archiving; a segment is archived as soon as it is closed |
| RTO (Recovery Time Objective) | ≤ 15 minutes | Restore base backup + replay archived WAL (measured PITR took under 2 minutes on test data) |
| Critical data | `customers`, `orders` tables in `bizdb` | Business transactions; referential integrity (FK) must survive restore |
| Retention | 7 days on-site | Enforced automatically by the backup script; off-site copy recommended for production (rsync/S3) |

### 2. Strategy Design

Three complementary layers:

1. **Physical full backups** (`pg_basebackup -Ft -z -Xnone`) — daily, the base for Point-In-Time Recovery. WAL is excluded from the backup itself because layer 2 provides it.
2. **Continuous WAL archiving** (`archive_mode = on`) — every closed 16 MB WAL segment is copied to `/backup/wal/`, giving near-zero RPO between full backups.
3. **Logical dumps** (`pg_dump -Fc`) — daily, custom format; enables selective restore of single tables and cross-version migration.

Every backup is **verified** with `pg_verifybackup` against its manifest immediately after creation.

### 3. Implementation

WAL archiving configuration:

```sql
ALTER SYSTEM SET wal_level = replica;
ALTER SYSTEM SET archive_mode = on;
ALTER SYSTEM SET archive_command = 'test ! -f /backup/wal/%f && cp %p /backup/wal/%f';
```

The `test ! -f` guard prevents overwriting an already-archived segment (a corruption safeguard required by PostgreSQL docs).

Automated backup script `/usr/local/bin/pg_backup.sh` (full + logical + verify + 7-day retention + logging):

```bash
#!/bin/bash
set -euo pipefail
cd /
TS=$(date +%Y%m%d_%H%M)
BASE=/backup/full/base_$TS
LOG=/backup/logs/backup_$TS.log
{
  echo "=== Backup started: $(date) ==="
  pg_basebackup -D "$BASE" -Ft -z -Xnone -v
  pg_dump -Fc bizdb -f /backup/full/bizdb_$TS.dump
  /usr/lib/postgresql/18/bin/pg_verifybackup -n "$BASE" && echo "VERIFY OK"
  find /backup/full -maxdepth 1 -name 'base_*' -mtime +7 -exec rm -rf {} \;
  find /backup/full -name 'bizdb_*.dump' -mtime +7 -delete
  find /backup/wal -type f -mtime +7 -delete
  echo "=== Backup finished: $(date) ==="
} >> "$LOG" 2>&1
```

Schedule (cron, daily at 02:00):

```
0 2 * * * postgres /usr/local/bin/pg_backup.sh
```

### 4. Restore Test — Point-In-Time Recovery

**Disaster simulation:** an extra order was inserted *after* the last full backup, the timestamp was recorded, then `DROP TABLE orders` destroyed 5001 rows.

**Recovery procedure:**

```bash
# 1. Stop the server, move the damaged data directory aside
sudo systemctl stop postgresql
sudo mv /var/lib/postgresql/18/main /var/lib/postgresql/18/main_broken

# 2. Restore the base backup
sudo -u postgres mkdir -m 700 /var/lib/postgresql/18/main
sudo -u postgres tar -xzf /backup/full/base_20260805_1455/base.tar.gz \
  -C /var/lib/postgresql/18/main

# 3. Configure the recovery target and start
cat >> postgresql.auto.conf <<'EOF'
restore_command = 'cp /backup/wal/%f %p'
recovery_target_time = '2026-08-05 14:57:23.897525+00'
recovery_target_action = 'promote'
EOF
touch /var/lib/postgresql/18/main/recovery.signal
sudo systemctl start postgresql
```

**Result:** the server replayed archived WAL and stopped exactly before the destructive transaction:

```
LOG:  recovery stopping before commit of transaction 771, time 2026-08-05 14:57:23.901224+00
LOG:  selected new timeline ID: 2
LOG:  database system is ready to accept connections
```

Verification: `orders` contained **5001 rows including the insert made after the backup** — RPO of effectively zero for this scenario. Note: after PITR the server continues on a **new timeline** (TL 2), which is expected behaviour.

### 5. Restore Procedures per Failure Scenario

| Scenario | Procedure | Layer used |
|---|---|---|
| Human error (DROP/DELETE) | PITR to a timestamp just before the mistake | Base backup + WAL |
| Single table corruption | `pg_restore --table=...` from the logical dump | `pg_dump -Fc` |
| Full disk/server loss | Restore latest base backup + replay all WAL (no target = recover to end) | Base backup + WAL |
| Datacenter loss | Same as above from the off-site copy | Off-site replica of `/backup` |

**Test schedule:** PITR drill quarterly; logical-restore drill monthly; backup verification runs automatically on every backup.

---

## Homework 2: PostgreSQL High Availability Cluster

### 1. Architecture

Three PostgreSQL nodes on one VM (simulating three servers), managed by Patroni with etcd as the DCS, fronted by PgBouncer:

```
Application
    |
PgBouncer :6432  <---updates--- pgbouncer-follow watcher
    |                                 | polls REST /leader
    v                                 v
node1 :5433   node2 :5434   node3 :5435     (Patroni REST: 8008/8009/8010)
    \_____________|_____________/
            streaming replication
                  |
              etcd :2379  (cluster state, leader key, TTL 30 s)
```

Key design decisions:

* **`synchronous_mode: true`** — Patroni designates one standby as synchronous; a commit is acknowledged only after that standby confirms it. This guarantees **zero data loss on failover** (verified: row count matched exactly after the leader was lost).
* **Fencing:** the DCS-based leader lock in etcd acts as the fencing mechanism — a node that cannot refresh the leader key demotes itself, and `use_pg_rewind: true` lets a former leader rejoin a diverged timeline.
* **Read load balancing:** both standbys run in hot standby and serve read-only queries (verified with `pg_is_in_recovery()` = `true` on ports 5433/5434 while 5435 was leader).

### 2. Implementation Notes

* One Patroni config per node (`/etc/patroni/node{1..3}.yml`), differing only in name, ports, and data directory; a **systemd template unit** `patroni@.service` runs all instances (`systemctl start patroni@node1` etc.).
* The Debian `patroni` package ships without an etcd client — `python3-etcd` had to be installed separately (initial error: *"Can not find suitable configuration of distributed configuration store"*).
* Node2 and node3 were bootstrapped automatically by Patroni via `pg_basebackup` from the leader.

**PgBouncer leader-following.** A static PgBouncer config pointing at the old leader was a single point of failure — after the first failover, writes failed with `server_login_retry`. Solution (equivalent of the Consul-template pattern from the Miro case study): a watcher service polls the Patroni REST endpoint `/leader` (HTTP 200 only on the current leader), rewrites `pgbouncer.ini`, and reloads PgBouncer on change:

```bash
for port in 8008 8009 8010; do
  if curl -sf -o /dev/null "http://127.0.0.1:$port/leader"; then
    LEADER_PG=$((port - 8008 + 5433))
    ...sed + systemctl reload pgbouncer...
  fi
done   # loop every 2 s
```

### 3. Failure Tests & Measurements

Load generator: one `INSERT ... RETURNING id` per second through PgBouncer.

| # | Scenario | Command | Outcome | Downtime |
|---|---|---|---|---|
| 1 | Patroni hard-stopped on leader (node1) | `systemctl stop patroni@node1` | node2 promoted (TL 1→2), node3 became sync standby | ~12 s (within TTL) |
| 2 | PostgreSQL process crash on leader (node2) | `pkill -9 postgres` | **No failover** — local Patroni restarted PostgreSQL before the etcd TTL expired (first line of defence: self-healing) | 16 s |
| 3 | Graceful leader shutdown (node2) | `systemctl stop patroni@node2` | Clean **switchover**: leader key released immediately, node3 promoted (TL 2→3), watcher repointed PgBouncer | ~0 s measured after stop completed |
| 4 | Former leader rejoin | `systemctl start patroni@node…` | Node rejoined as a streaming replica on the new timeline, lag 0 | n/a |

**Data-loss check:** after test 1, `SELECT count(*)` through the new leader returned exactly the number of successfully acknowledged inserts — no committed transaction was lost (synchronous replication).

### 4. Analysis

* Downtime is bounded by the DCS parameters (`ttl: 30`, `loop_wait: 10`, `retry_timeout: 10`). Lowering them speeds up failover at the cost of more false positives on a flaky network.
* A process crash is cheaper than a machine loss: Patroni's local restart resolved it in 16 s without disturbing cluster topology.
* Graceful shutdowns are effectively free — the leader hands over the lock, so planned maintenance causes near-zero interruption.
* Remaining SPOFs in this lab setup: single etcd instance and single PgBouncer (production would use a 3-node etcd cluster and ≥2 PgBouncers behind a load balancer, as in the Miro case study).

### 5. Operational Procedures (SOP)

```bash
# Cluster state
patronictl -c /etc/patroni/node1.yml list

# Planned switchover (maintenance)
patronictl -c /etc/patroni/node1.yml switchover

# Restart a single node without failover
patronictl -c /etc/patroni/node1.yml restart pg-ha-cluster node2

# Reinitialize a broken replica from the leader
patronictl -c /etc/patroni/node1.yml reinit pg-ha-cluster node2

# Which node is leader (REST)
curl -s http://127.0.0.1:8008/leader -o /dev/null -w "%{http_code}\n"
```

### 6. Disaster Recovery Plan (DRP)

1. **One node lost** — no action required; automatic failover (≤ TTL) or self-healing. Rebuild the node with `patronictl reinit` when hardware returns.
2. **Two nodes lost** — cluster still serves from the surviving leader; restore quorum ASAP (with a real 3-node etcd, losing etcd quorum would freeze leader elections).
3. **All nodes / site lost** — restore from the Homework 1 backup strategy: base backup + WAL archive → PITR, then re-bootstrap the Patroni cluster from the restored primary.

---

## Summary

* Designed and implemented a three-layer backup strategy (base backups, continuous WAL archiving, logical dumps) with automatic verification, retention, and scheduling; proved it with a successful Point-In-Time Recovery that stopped one transaction before a simulated `DROP TABLE`.
* Built a three-node PostgreSQL HA cluster with Patroni + etcd, synchronous replication, automatic failover, and PgBouncer connection pooling that follows the leader automatically.
* Measured real failover behaviour: self-healing after a process crash (16 s, no failover), DCS-driven failover after node loss (~12 s), and near-instant planned switchover — with zero committed-data loss throughout.