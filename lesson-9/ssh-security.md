## 1. Public and private keys

SSH can authenticate a user with a cryptographic key pair instead of a password:

- **Private key** (`~/.ssh/learning_key`) — stays exclusively on the client machine, is never transmitted over the network or shared. It should be protected with **600** permissions and an additional password (passphrase).
- **Public key** (`~/.ssh/learning_key.pub`) — copied to the server into the `~/.ssh/authorized_keys` file. It is public; its disclosure poses no threat.

Login mechanism: the server sends a challenge encrypted with the public key, and the client proves possession of the private key by decrypting it. The password is never transmitted.

## 2. Comparison: SSH keys vs passwords

|Criterion|Password|SSH key|
|---|---|---|
|Resistance to guessing/brute-force|low|very high (4096-bit)|
|Transmitting the secret over the network|yes (interception risk)|no|
|Susceptibility to phishing|high|low|
|Convenience (login without typing)|no|yes (with ssh-agent)|
|Automation capability|limited|yes|

## 3. Procedures for secure key management

- The private key always with **600** permissions; SSH refuses to use keys that are "too open".
- Protect the private key with a **passphrase** — it protects the key even after the file is stolen.
- Use `ssh-agent` to conveniently keep an unlocked key in session memory.
- Do not copy the private key between machines — generate a separate one for each device.
- On the server side in `/etc/ssh/sshd_config`, recommended: `PermitRootLogin no`, `PasswordAuthentication no` (after confirming the key works!), `MaxAuthTries 3`.

## 4. Commands for debugging SSH problems

```bash
# Verbose mode — shows the successive stages of authentication
ssh -v -i ~/.ssh/learning_key user@host

# Even more detail
ssh -vvv -i ~/.ssh/learning_key user@host

# Checking private key permissions (must be 600)
ls -l ~/.ssh/learning_key

# SSH server logs
journalctl -u ssh -n 20 --no-pager
sudo cat /var/log/auth.log | grep sshd   # Debian/Ubuntu

# Test whether the SSH port is open
nc -zv host 22

# Server service status
sudo systemctl status ssh
```

## 5. Common error messages

- `WARNING: UNPROTECTED PRIVATE KEY FILE!` — the private key has overly open permissions; fix with `chmod 600`.
- `Permission denied (publickey)` — the public key is not in `authorized_keys` on the server, or the server does not accept this method.
- `Host key verification failed` — the host fingerprint has changed relative to `~/.ssh/known_hosts`.