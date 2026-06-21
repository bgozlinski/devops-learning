## Homework 1 — Compression, archiving and backup

### Step 1 — Create the test project structure

**Commands:**

```bash
mkdir -p ~/learning_project/{src,docs,config,data,logs}
echo "Source code" > ~/learning_project/src/main.sh
echo "Documentation" > ~/learning_project/docs/README.md
echo "Config=value" > ~/learning_project/config/settings.conf
dd if=/dev/zero of="$HOME/learning_project/data/sample.dat" bs=1M count=20
```

**Output:**

```text
20+0 records in
20+0 records out
20971520 bytes (21 MB, 20 MiB) copied, 0.154574 s, 136 MB/s

# ls -la ~/learning_project/
drwxrwxr-x config
drwxrwxr-x data
drwxrwxr-x docs
drwxrwxr-x logs
drwxrwxr-x src
```

**Explanation:**

`mkdir -p` with brace expansion `{src,docs,config,data,logs}` creates five subdirectories in a single command. `dd if=/dev/zero ... bs=1M count=20` generates a **20 MiB** file filled with zeros — it serves as a large, easily compressible payload for comparing the algorithms.

> **Practical note:** in this environment `dd` did not expand the tilde in the `of=~/...` argument (`No such file or directory`). The fix was to use the `$HOME` variable instead of `~` — unlike the tilde, it is expanded regardless of the quoting context. This convention was applied in the following commands.

### Step 2 — Size of the original data

**Command:**

```bash
du -sh "$HOME/learning_project/"
```

**Output:**

```text
21M     /home/bartek/learning_project/
```

**Explanation:**

`du -sh` (`-s` = summary, `-h` = human-readable) shows that the whole directory takes **21 MB** — almost entirely the `sample.dat` file, since the remaining text files are only a dozen-or-so bytes each.

### Step 3 — Tar archive (uncompressed)

**Commands:**

```bash
tar -cvf "$HOME/backup_raw.tar" "$HOME/learning_project/"
ls -lh "$HOME/backup_raw.tar"
```

**Output:**

```text
tar: Removing leading `/' from member names
home/bartek/learning_project/
home/bartek/learning_project/data/sample.dat
home/bartek/learning_project/src/main.sh
home/bartek/learning_project/docs/README.md
home/bartek/learning_project/config/settings.conf
...

-rw-rw-r-- 1 bartek bartek 21M backup_raw.tar
```

**Explanation:**

`tar -cvf` (`-c` create, `-v` verbose, `-f` file) packs the directory into **one** archive without compression — the size of **21 MB** is practically equal to the original. The `Removing leading '/'` message is a tar safeguard: absolute paths are converted to relative ones so that extraction does not overwrite system files.

### Step 4 — Tar.gz archive (gzip)

**Commands:**

```bash
tar -czvf "$HOME/backup_gzip.tar.gz" "$HOME/learning_project/"
ls -lh "$HOME/backup_gzip.tar.gz"
```

**Output:**

```text
-rw-rw-r-- 1 bartek bartek 21K backup_gzip.tar.gz
```

**Explanation:**

The `-z` flag adds gzip compression. The size dropped from 21 MB to **21 KB** — a file of all zeros compresses extremely well (gzip encodes repetitive sequences).

### Step 5 — Tar.bz2 archive (bzip2)

**Commands:**

```bash
tar -cjvf "$HOME/backup_bzip2.tar.bz2" "$HOME/learning_project/"
ls -lh "$HOME/backup_bzip2.tar.bz2"
```

**Output:**

```text
-rw-rw-r-- 1 bartek bartek 422 backup_bzip2.tar.bz2
```

**Explanation:**

The `-j` flag uses bzip2 — a slower but more effective algorithm. Here the result is only **422 bytes**, even less than gzip.

### Step 6 — Size comparison and checksum

**Commands:**

```bash
ls -lh "$HOME/backup_raw.tar" "$HOME/backup_gzip.tar.gz" "$HOME/backup_bzip2.tar.bz2"
md5sum "$HOME/backup_gzip.tar.gz"
```

**Output:**

```text
-rw-rw-r-- 1 bartek bartek  422 backup_bzip2.tar.bz2
-rw-rw-r-- 1 bartek bartek  21K backup_gzip.tar.gz
-rw-rw-r-- 1 bartek bartek  21M backup_raw.tar

a248a91a1997e8e784a5e80afecd03d4  backup_gzip.tar.gz
```

**Format comparison:**

|Format|Size|Ratio|Algorithm|
|---|---|---|---|
|`.tar` (uncompressed)|21 MB|1×|none|
|`.tar.gz` (gzip)|21 KB|~1000×|fast, good|
|`.tar.bz2` (bzip2)|422 B|~50000×|slower, better|

**Explanation:**

The result confirms the lesson's point: **archiving** (tar) combines files without reducing size, and only **compression** (gzip/bzip2) reduces it. bzip2 is the smallest, uncompressed tar the largest. `md5sum` produces the archive checksum — used for later integrity verification.

### Step 7 — Extraction and verification

**Commands:**

```bash
mkdir -p "$HOME/restore"
tar -xzvf "$HOME/backup_gzip.tar.gz" -C "$HOME/restore/"
diff -r "$HOME/learning_project/" "$HOME/restore/home/bartek/learning_project/"
```

**Output:**

```text
home/bartek/learning_project/data/sample.dat
home/bartek/learning_project/src/main.sh
home/bartek/learning_project/docs/README.md
home/bartek/learning_project/config/settings.conf
...

# diff -r — no output
```

**Explanation:**

`tar -xzvf ... -C` extracts to the specified directory. Because tar removed the leading `/`, the files end up under `restore/home/bartek/learning_project/` — that is why this exact path was passed to `diff`. `diff -r` printed nothing, which means the **extracted files are bit-for-bit identical** to the original.

### Step 8 — Listing archive contents without extraction

**Command:**

```bash
tar -tzvf "$HOME/backup_gzip.tar.gz"
```

**Output:**

```text
drwxrwxr-x bartek/bartek        0 home/bartek/learning_project/
-rw-rw-r-- bartek/bartek 20971520 home/bartek/learning_project/data/sample.dat
-rw-rw-r-- bartek/bartek       12 home/bartek/learning_project/src/main.sh
-rw-rw-r-- bartek/bartek       14 home/bartek/learning_project/docs/README.md
-rw-rw-r-- bartek/bartek       13 home/bartek/learning_project/config/settings.conf
```

**Explanation:**

The `-t` flag (list) shows the archive contents **without** extracting it — useful for previewing what is inside and verifying the original file sizes (e.g. `sample.dat` = 20971520 B = 20 MiB).

### Advanced level A — GPG encryption

**Commands:**

```bash
gpg -c "$HOME/backup_gzip.tar.gz"
gpg -d "$HOME/backup_gzip.tar.gz.gpg" > "$HOME/restored.tar.gz"
md5sum "$HOME/backup_gzip.tar.gz" "$HOME/restored.tar.gz"
```

**Output:**

```text
gpg: AES256.CFB encrypted data
gpg: encrypted with 1 passphrase

a248a91a1997e8e784a5e80afecd03d4  backup_gzip.tar.gz
a248a91a1997e8e784a5e80afecd03d4  restored.tar.gz
```

**Explanation:**

`gpg -c` encrypts symmetrically (with a password, **AES256** algorithm), creating a `.gpg` file. `gpg -d` decrypts it. **Both MD5 checksums are identical** — the encrypt → decrypt cycle preserved the file 100%, with no data loss.

### Advanced level B — rsync instead of tar

**Commands:**

```bash
rsync -avz "$HOME/learning_project/" "$HOME/backup_rsync/"
du -sh "$HOME/backup_rsync/"
diff -r "$HOME/learning_project/" "$HOME/backup_rsync/"
```

**Output:**

```text
sending incremental file list
created directory /home/bartek/backup_rsync
./
config/settings.conf
data/sample.dat
docs/README.md
src/main.sh

sent 1,171 bytes  received 167 bytes  2,676.00 bytes/sec
total size is 20,971,559  speedup is 15,673.81

21M     /home/bartek/backup_rsync/

# diff -r — no output
```

**Explanation:**

`rsync -avz` (`-a` preserve attributes/recursion, `-v` verbose, `-z` compression during transfer) synchronizes directories. Unlike tar, it does not create a single archive — it mirrors the structure 1:1. `diff -r` with no output confirms the match. The high `speedup` comes from compressing the transfer of all-zero data.

---

## Homework 2 — SSH: configuration and security

### Step 1 — Generating the SSH key pair

**Commands:**

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/learning_key -C "learning@devops"
chmod 600 ~/.ssh/learning_key
chmod 644 ~/.ssh/learning_key.pub
ls -l ~/.ssh/learning_key ~/.ssh/learning_key.pub
```

**Output:**

```text
Your identification has been saved in /home/bartek/.ssh/learning_key
Your public key has been saved in /home/bartek/.ssh/learning_key.pub
The key fingerprint is:
SHA256:76RJSUtJ13nftW2dc1xKePC9QRTJDxExB+I3iXXtih0 learning@devops

-rw------- 1 bartek bartek 3434 .ssh/learning_key
-rw-r--r-- 1 bartek bartek  741 .ssh/learning_key.pub
```

**Explanation:**

`ssh-keygen -t rsa -b 4096` generates a 4096-bit RSA key pair. The private key received **600** permissions (only the owner reads/writes), and the public one **644** (readable by everyone — which is safe, the public key is meant to be public). The key was additionally secured with a **passphrase**, visible in the later tests (SSH asks for the key password, not the account one).

### Step 2 — SSH server status

**Command:**

```bash
sudo systemctl status ssh --no-pager
```

**Output:**

```text
● ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/usr/lib/systemd/system/ssh.service; enabled; preset: enabled)
     Active: active (running)
   Main PID: 1828 (sshd)
```

**Explanation:**

The `ssh` service is active (`active (running)`) and enabled at startup (`enabled`), so the host can accept SSH connections — which makes the `localhost` tests possible.

### Step 3 — Copying the public key (ssh-copy-id)

**Command:**

```bash
ssh-copy-id -i ~/.ssh/learning_key.pub bartek@localhost
```

**Output:**

```text
The authenticity of host 'localhost (127.0.0.1)' can't be established.
ED25519 key fingerprint is: SHA256:EEG2LHmuAyjPm64pP400HbmRWcekRlXQ5Bblj0spC54
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Number of key(s) added: 1
```

**Explanation:**

`ssh-copy-id` appends the public key to `~/.ssh/authorized_keys` on the server. On the first connection SSH asks to verify the host fingerprint (the TOFU mechanism — Trust On First Use), which after confirmation is saved into `~/.ssh/known_hosts`.

### Step 4 — Key-based login test

**Command:**

```bash
ssh -i ~/.ssh/learning_key bartek@localhost "echo POLACZENIE_OK; hostname; whoami"
```

**Output:**

```text
Enter passphrase for key '/home/bartek/.ssh/learning_key':
POLACZENIE_OK
linux1
bartek
```

**Explanation:**

Login succeeded with the **key** (not the account password) — SSH only asked for the passphrase protecting the private key. The remotely executed commands returned the correct values (`hostname` = linux1, `whoami` = bartek).

### Step 5 — SCP test

**Commands:**

```bash
echo "test scp file" > ~/file.txt
scp -i ~/.ssh/learning_key ~/file.txt bartek@localhost:/tmp/
ls -l /tmp/file.txt
```

**Output:**

```text
file.txt                          100%   17    10.1KB/s   00:00
-rw-rw-r-- 1 bartek bartek 17 /tmp/file.txt
```

**Explanation:**

`scp` (Secure Copy) transfers the file over an encrypted SSH channel, using the same key. The file reached `/tmp/` on the server in full (17 bytes).

### Step 6 — Configuration file ~/.ssh/config

**Commands:**

```bash
cat >> ~/.ssh/config << 'EOF'
Host learning-server
    HostName localhost
    User bartek
    IdentityFile ~/.ssh/learning_key
    Port 22
    StrictHostKeyChecking no
EOF
chmod 600 ~/.ssh/config
ssh learning-server "echo ALIAS_DZIALA; hostname"
```

**Output:**

```text
ALIAS_DZIALA
linux1
```

**Explanation:**

The `~/.ssh/config` file lets you define a connection **alias** — instead of the long `ssh -i ~/.ssh/learning_key bartek@localhost`, `ssh learning-server` is enough. SSH automatically substitutes HostName, User, IdentityFile and Port from the entry.

### Step 7 — Security exercise: incorrect key permissions

**Commands:**

```bash
chmod 644 ~/.ssh/learning_key
ssh -i ~/.ssh/learning_key bartek@localhost "echo test"
chmod 600 ~/.ssh/learning_key
```

**Output:**

```text
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@         WARNING: UNPROTECTED PRIVATE KEY FILE!          @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Permissions 0644 for '/home/bartek/.ssh/learning_key' are too open.
This private key will be ignored.
Load key "/home/bartek/.ssh/learning_key": bad permissions
bartek@localhost's password:
```

**Explanation:**

After loosening permissions to **644** (readable by others) SSH **refused to use the key** and fell back to password login. This is a deliberate mechanism: a private key accessible to other users is a security hole. Fix: `chmod 600`.

### Step 8 — SSH log analysis

**Command:**

```bash
journalctl -u ssh -n 20 --no-pager
```

**Output:**

```text
Accepted publickey for bartek from 127.0.0.1 ssh2: RSA SHA256:76RJSUtJ13nftW2dc1xKePC9QRTJDxExB+I3iXXtih0
pam_unix(sshd:session): session opened for user bartek(uid=1000)
Accepted password for bartek from 127.0.0.1 ssh2
pam_unix(sshd:session): session closed for user bartek
```

**Explanation:**

The logs clearly distinguish the authentication methods: `Accepted publickey` (successful key login, with a fingerprint matching the generated one) and `Accepted password` (fallback after breaking the key permissions). This confirms the effectiveness of both paths and the correctness of the security exercise.

### Advanced level A — SSH timeout (ServerAliveInterval)

**Commands:**

```bash
cat >> ~/.ssh/config << 'EOF'
Host learning-timeout
    HostName localhost
    User bartek
    IdentityFile ~/.ssh/learning_key
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
```

**Explanation:**

`ServerAliveInterval 60` sends a keep-alive packet every 60 s, and `ServerAliveCountMax 3` drops the session after three missing responses (i.e. after ~180 s of silence). This protects against "hanging" sessions after a loss of connectivity.

### Advanced level B — SSH tunneling (port forwarding)

**Commands:**

```bash
ssh -i ~/.ssh/learning_key -f -N -L 8080:localhost:22 bartek@localhost
ss -tlnp | grep 8080
pkill -f "8080:localhost:22"
```

**Output:**

```text
LISTEN 0  128  127.0.0.1:8080  0.0.0.0:*  users:(("ssh",pid=64422,fd=5))
LISTEN 0  128      [::1]:8080     [::]:*  users:(("ssh",pid=64422,fd=4))

# after pkill:
tunnel closed
```

**Explanation:**

`-L 8080:localhost:22` creates a **local port forwarding** tunnel: traffic to local port 8080 is forwarded over an encrypted SSH channel to port 22 on the server side. The `-f` (background) and `-N` (no remote command, tunnel only) flags run it as a background service. `ss -tlnp` confirms the listener on 8080 (the `ssh` process), and `pkill` closes the tunnel correctly.

---

## Summary

**Homework 1** completed a full backup cycle: creating test data, comparing three archive formats (tar 21 MB → gzip 21 KB → bzip2 422 B), verifying integrity (`diff`, `md5sum`), GPG encryption (AES256, MD5 checksum preserved) and rsync synchronization. The key distinction was confirmed: archiving combines files, compression reduces their size.

**Homework 2** covered secure SSH access: generating a 4096-bit RSA key with a passphrase, distributing the key (`ssh-copy-id`), testing key-based login and SCP, configuring aliases in `~/.ssh/config`, a security exercise (refusal to use a key with overly open permissions), log analysis (`Accepted publickey` vs `Accepted password`), session timeout and port tunneling.