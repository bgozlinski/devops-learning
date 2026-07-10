# Lesson 16 — Databases (MySQL): Homework Report

## Task 1 — Blog database

### Installation

MySQL was not present on the VM (`Unit mysql.service could not be found`), so it was installed:

```bash
sudo apt update && sudo apt install mysql-server -y
systemctl status mysql --no-pager   # Active: running, enabled at boot
```

MySQL 8.4 on Ubuntu authenticates root via `auth_socket`, so `sudo mysql` logs in without a password.

### Schema

Database created with explicit UTF-8 to avoid Polish character encoding issues:

```sql
CREATE DATABASE blog CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

Six tables, created in dependency order:

| Table | Purpose | Relations |
|---|---|---|
| `users` | author/commenter profiles | — |
| `categories` | post categories | — |
| `tags` | post tags | — |
| `posts` | blog articles | FK → `users`, FK → `categories` (1:N) |
| `comments` | comments on posts | FK → `posts`, FK → `users` (1:N) |
| `post_tags` | junction table | composite PK, FK → `posts`, FK → `tags` (M:N) |

```sql
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    display_name VARCHAR(100),
    bio TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE categories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE tags (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE posts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    category_id INT,
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    published_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    views INT NOT NULL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (category_id) REFERENCES categories(id)
);

CREATE TABLE comments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE post_tags (
    post_id INT NOT NULL,
    tag_id INT NOT NULL,
    PRIMARY KEY (post_id, tag_id),
    FOREIGN KEY (post_id) REFERENCES posts(id),
    FOREIGN KEY (tag_id) REFERENCES tags(id)
);
```

### Test data

Seeded 4 users, 4 categories, 6 tags, 6 posts, 7 comments, 10 post-tag links. Verified with a single multi-subquery count:

```sql
SELECT
  (SELECT COUNT(*) FROM users) AS users,
  (SELECT COUNT(*) FROM categories) AS categories,
  (SELECT COUNT(*) FROM tags) AS tags,
  (SELECT COUNT(*) FROM posts) AS posts,
  (SELECT COUNT(*) FROM comments) AS comments,
  (SELECT COUNT(*) FROM post_tags) AS post_tags;
-- 4 | 4 | 6 | 6 | 7 | 10
```

Polish diacritics (`Wiśniewska`, `wyświetleń`) stored and displayed correctly thanks to `utf8mb4`.

### Analytical queries

**Top posts by views** (JOIN across three tables):

```sql
SELECT p.title, u.username, c.name AS kategoria, p.views
FROM posts p
JOIN users u ON p.user_id = u.id
LEFT JOIN categories c ON p.category_id = c.id
ORDER BY p.views DESC
LIMIT 5;
```

**Most active authors** — `LEFT JOIN` deliberately used so authors with zero posts still appear (user `mwisniewska` showed `0 | 0`, which an `INNER JOIN` would have hidden):

```sql
SELECT u.username, COUNT(p.id) AS liczba_postow,
       COALESCE(SUM(p.views), 0) AS suma_wyswietlen
FROM users u
LEFT JOIN posts p ON u.id = p.user_id
GROUP BY u.id, u.username
ORDER BY suma_wyswietlen DESC;
```

**Categories ranked by posts and comments** (chained LEFT JOINs with `COUNT(DISTINCT ...)` to avoid row-multiplication from the join):

```sql
SELECT c.name, COUNT(DISTINCT p.id) AS posty, COUNT(com.id) AS komentarze
FROM categories c
LEFT JOIN posts p ON c.id = p.category_id
LEFT JOIN comments com ON p.id = com.post_id
GROUP BY c.id, c.name
ORDER BY posty DESC, komentarze DESC;
```

### View, subquery, indexes

**View** — posts with comment counts:

```sql
CREATE VIEW posts_with_comments AS
SELECT p.id, p.title, u.username AS autor, c.name AS kategoria,
       p.views, COUNT(com.id) AS liczba_komentarzy
FROM posts p
JOIN users u ON p.user_id = u.id
LEFT JOIN categories c ON p.category_id = c.id
LEFT JOIN comments com ON p.id = com.post_id
GROUP BY p.id, p.title, u.username, c.name, p.views;
```

**Subquery** — posts with above-average comment count (average computed over posts that have comments, 7/4 = 1.75; returned posts with 2 and 3 comments):

```sql
SELECT * FROM posts_with_comments
WHERE liczba_komentarzy > (
    SELECT AVG(cnt) FROM (
        SELECT COUNT(*) AS cnt FROM comments GROUP BY post_id
    ) AS sub
);
```

**Indexes** on columns used in WHERE/JOIN:

```sql
CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_posts_category_id ON posts(category_id);
CREATE INDEX idx_comments_post_id ON comments(post_id);
CREATE INDEX idx_posts_published_at ON posts(published_at);
```

Note: InnoDB automatically creates indexes on FK columns, so the FK-column indexes partially duplicate implicit ones — harmless here, but on large tables redundant indexes cost write performance and disk space.

---

## Task 2 — Administration and security

### Tiered users

```sql
CREATE USER 'blog_admin'@'localhost' IDENTIFIED BY '<password>';
GRANT ALL PRIVILEGES ON blog.* TO 'blog_admin'@'localhost';

CREATE USER 'blog_dev'@'localhost' IDENTIFIED BY '<password>';
GRANT SELECT, INSERT, UPDATE ON blog.* TO 'blog_dev'@'localhost';

CREATE USER 'blog_audit'@'localhost' IDENTIFIED BY '<password>';
GRANT SELECT ON blog.* TO 'blog_audit'@'localhost';

FLUSH PRIVILEGES;
```

**Negative testing** (each user logged in separately):

| User | Allowed | Denied (ERROR 1142) |
|---|---|---|
| `blog_audit` | `SELECT` | `INSERT`, `DROP TABLE` |
| `blog_dev` | `SELECT`, `INSERT`, `UPDATE` | `DELETE` |

All denials returned the expected `ERROR 1142 (42000): ... command denied`.

### Backup and restore

Full dump, then restore into a fresh database under a different name:

```bash
mysqldump -u blog_admin -p blog > ~/backups/blog_backup.sql
sudo mysql -e "CREATE DATABASE blog_restore CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql blog_restore < ~/backups/blog_backup.sql
```

Integrity verified: 7 objects restored (6 tables + the `posts_with_comments` view), `posts=6`, `comments=7`, `users=4` — matching the source.

**Gotcha #1 — grant scope:** restoring as `blog_admin` into `blog_restore` failed with `ERROR 1044 (Access denied)`, because its grants cover only `blog.*`. Restore was done as root via the auth socket. Least-privilege accounts can't be reused across databases — by design.

### Automated backup script

`~/backups/mysql_backup.sh` — dated, gzipped dumps with 7-day retention:

```bash
#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${1:-blog}"
BACKUP_DIR="$HOME/backups"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz"
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"
echo "[$(date '+%F %T')] Start backupu bazy: $DB_NAME"

if mysqldump --defaults-extra-file="$HOME/.my.cnf" --no-tablespaces "$DB_NAME" | gzip > "$BACKUP_FILE"; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "[$(date '+%F %T')] OK: $BACKUP_FILE ($SIZE)"
else
    echo "[$(date '+%F %T')] BŁĄD: backup nie powiódł się" >&2
    rm -f "$BACKUP_FILE"
    exit 1
fi

DELETED=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -mtime +"$RETENTION_DAYS" -print -delete | wc -l)
echo "[$(date '+%F %T')] Usunięto starych backupów: $DELETED"
```

Credentials live in `~/.my.cnf` (`chmod 600`) instead of the command line, avoiding the "password on the command line can be insecure" warning and shell history leakage.

**Gotcha #2 — `#` in option files:** the first run failed with `ERROR 1045 (Access denied)`. Cause: in MySQL option files `#` starts a comment, so a password containing `#` was silently truncated (`Adm1n#...` → `Adm1n`). Fix: quote the value — `password="Adm1n#..."`.

**Gotcha #3 — tablespaces warning:** `mysqldump` as a non-PROCESS user warns `Access denied; you need ... PROCESS privilege ... when trying to dump tablespaces`. Data is unaffected; `--no-tablespaces` silences it cleanly (standard since MySQL 8 when dumping with limited accounts).

Verified run:

```
[2026-07-10 00:19:49] Start backupu bazy: blog
[2026-07-10 00:19:49] OK: /home/bartek/backups/blog_2026-07-10_00-19-49.sql.gz (4.0K)
[2026-07-10 00:19:49] Usunięto starych backupów: 0
```

### Monitoring

```bash
sudo systemctl status mysql          # Active: running, enabled
mysql -e "SHOW PROCESSLIST;"         # active connections
mysql -e "SHOW TABLE STATUS FROM blog\G"
```

`SHOW TABLE STATUS` interpretation: all tables on InnoDB engine; `Rows` values are estimates (InnoDB doesn't keep exact counts); `Auto_increment` shows the next ID to be assigned; `Collation: utf8mb4_unicode_ci` confirms encoding; `Index_length` grows with added indexes (e.g. 32 KB on `comments` after indexing `post_id`).

### Documentation

`~/backups/DB_ADMIN.md` created on the VM, covering the user/privilege matrix, backup procedure (including the option-file quoting caveat and grant-scope restore limitation), and monitoring commands.

---

## Key takeaways

- **`LEFT JOIN` vs `INNER JOIN` matters for reporting** — zero-count rows (inactive authors, empty categories) only appear with LEFT JOIN.
- **Grant scope is a hard boundary** — a per-database admin cannot dump-and-restore across databases; plan a dedicated backup account or use root via socket.
- **MySQL option files treat `#` as a comment start** — always quote passwords containing special characters in `.my.cnf`.
- **`--no-tablespaces`** is the standard flag when dumping with least-privilege accounts on MySQL 8+.
- **A backup is only real after a restore test** — the `blog_restore` round-trip confirmed the dump is usable, not just present.

## Next steps

- Schedule `mysql_backup.sh` via cron or a systemd timer (daily full dump).
- Lesson 17 preview: PostgreSQL in depth, NoSQL (MongoDB, Redis), replication and fault tolerance.