# apt-herd

Run `apt update`, `full-upgrade`, `autoremove`, and `clean` across multiple Debian hosts over SSH.

## Quick start

```bash
git clone git@github.com:hardenedpenguin/apt-herd.git
cd apt-herd
sudo apt install ruby3.3-dev build-essential
sudo gem3.3 install net-ssh ed25519 bcrypt_pbkdf
chmod +x apt-herd.rb
```

**1. List your hosts** — edit `apt-herd.yaml`:

```yaml
hosts:
  - 100.114.117.78
  - 100.82.15.99
```

Or set `use_ssh_config: true` and use `Host` entries in `~/.ssh/config`.

**2. Auth** — pick one:

| Method | What to do |
|--------|------------|
| **SSH keys** | Keys in `~/.ssh` or `IdentityFile` in SSH config. Remote user needs **passwordless sudo** (`NOPASSWD` in sudoers). |
| **Passwords** | Copy `apt-herd-credentials.json.example` → `apt-herd-credentials.json`, fill in `user`, `password`, `sudo_password`. Required for cron. |

**3. Run**

```bash
./apt-herd.rb -n    # dry run — check hosts and commands
./apt-herd.rb       # update all hosts
```

## Requirements

- Ruby 3.3+ on Debian (use `gem3.3`; match suffix to `ruby --version`)
- SSH access to targets (`apt`, `sudo` on each host)
- `ruby3.3-dev` and `build-essential` on the machine running apt-herd (native gems need headers and `make`)

## Install

```bash
sudo apt install ruby3.3-dev build-essential
sudo gem3.3 install net-ssh ed25519 bcrypt_pbkdf
chmod +x apt-herd.rb
```

If a previous install failed with `Permission denied` under `/var/lib/gems/`:

```bash
sudo rm -rf /var/lib/gems/3.3.0/gems/bcrypt_pbkdf-* /var/lib/gems/3.3.0/gems/ed25519-*
sudo gem3.3 install net-ssh ed25519 bcrypt_pbkdf
```

## Config (`apt-herd.yaml`)

| Key | Description |
|-----|-------------|
| `hosts` | List of IPs or hostnames |
| `use_ssh_config` | If `true`, merge hosts from `~/.ssh/config` |
| `ssh` | Optional `port`, `user`, `keys`, `timeout` (default timeout: 10s; use `-t 30` for slow VPN) |
| `credentials` | Path to credentials JSON (optional; auto-loads `apt-herd-credentials.json` if present) |

Per-host SSH user/port/keys come from `~/.ssh/config` when available.

## Password auth (`apt-herd-credentials.json`)

For hosts without SSH keys, or when running from cron:

```bash
cp apt-herd-credentials.json.example apt-herd-credentials.json
chmod 600 apt-herd-credentials.json
```

Top-level fields apply to all hosts; override per host under `hosts` (key = IP or hostname from your list):

```json
{
  "user": "asl",
  "password": "ssh-password",
  "sudo_password": "sudo-password",
  "hosts": {
    "100.114.117.78": {}
  }
}
```

`sudo_password` enables `sudo -S` (no TTY). If omitted, `password` is used for sudo too.

## Usage

```bash
./apt-herd.rb [options] [host1 host2 ...]
```

```bash
./apt-herd.rb              # all configured hosts
./apt-herd.rb host1 host2  # specific hosts only
./apt-herd.rb -n           # dry run
./apt-herd.rb -v           # show apt output
./apt-herd.rb -t 30        # longer SSH timeout (VPN/Tailscale)
```

| Option | Description |
|--------|-------------|
| `-u USER` | SSH user |
| `-p PORT` | SSH port |
| `-k KEY` | SSH key path (repeatable) |
| `-t SEC` | SSH timeout (default 10) |
| `-n` | Dry run |
| `-v` | Verbose |
| `-c PATH` | Config file |
| `-j PATH` | Credentials JSON |
| `--ssh-config` | Use `~/.ssh/config` hosts |
| `-h` | Help |

Exit 0 on success; 1 if any host fails.

## Cron

Weekly Monday 01:00 with log in the repo (use credentials JSON — no interactive passwords):

```
0 1 * * 1 cd /path/to/apt-herd && ./apt-herd.rb >> apt-herd.log 2>&1
```

## Troubleshooting

| Error | Fix |
|-------|-----|
| `cannot load such file -- net/ssh` | Run `sudo gem3.3 install net-ssh ed25519 bcrypt_pbkdf` |
| `mkmf.rb can't find header files` | `sudo apt install ruby3.3-dev build-essential` |
| `sudo: a terminal is required` | Add `sudo_password` to credentials JSON |
| `Connection timeout` | Host offline or slow VPN — try `-t 30` |
| `No hosts given` | Add hosts to `apt-herd.yaml` or enable `use_ssh_config` |
| SSH password prompt | Use credentials JSON or set up SSH keys |
