# apt-herd

Herds **apt update** and **apt upgrade** across multiple Debian-based systems over SSH—VPN, local LAN, or anywhere you can reach via SSH. One command updates all configured hosts.

## What it does

- SSHs to each host and runs: `sudo apt-get update` then `sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y`
- Hosts come from `apt-herd.yaml`, `~/.ssh/config` (Host entries), CLI arguments, or a mix
- Uses your existing SSH config (user, port, keys, hostname) per host when available

## Requirements

- **Ruby 2.6 or newer** — apt-herd depends on net-ssh 7.x, which requires Ruby >= 2.6. Check with `ruby --version`.
- SSH access to the target hosts (key-based or password)
- Targets must be Debian/Ubuntu (or compatible) with `apt-get` and `sudo`

## Installation

On Debian and Ubuntu, Ruby-related commands are often **version-suffix** binaries (for example `bundle3.3`, `gem3.3`) instead of plain `bundle` / `gem`. Use the executable that matches your installed Ruby (see `ruby --version` and `ls /usr/bin/bundle*` or `command -v bundle3.3`).

**Option A – Bundler (recommended)**

```bash
bundle install --gemfile=Gemfile.apt-herd
```

If `bundle` is not on your `PATH`, substitute the versioned name your distro provides, for example:

```bash
bundle3.3 install --gemfile=Gemfile.apt-herd
```

**Option B – Gem only**

```bash
gem install net-ssh ed25519 bcrypt_pbkdf
```

If needed, use `gem3.3` (or your Ruby’s `gem`) instead of `gem`.

Make the script executable if needed:

```bash
chmod +x apt-herd.rb
```

## Configuration

Copy or edit `apt-herd.yaml` in the same directory as the script (or pass a config path with `-c`).

| Key | Description |
|-----|-------------|
| `ssh` | Optional: `port`, `user`, `keys`, `timeout` (used when a host isn’t in SSH config) |
| `use_ssh_config` | If `true`, host names and SSH options are read from `~/.ssh/config` |
| `ssh_config_path` | Override path to SSH config (default: `~/.ssh/config`) |
| `hosts` | Optional list of hostnames or `{ host: "...", user: "..." }` entries |

Example `apt-herd.yaml`:

```yaml
use_ssh_config: true

ssh:
  port: 22
  timeout: 10

hosts:
  - 192.168.1.10
  - home-server.local
```

Hosts from `hosts` and from SSH config (when `use_ssh_config: true`) are merged. Wildcard `Host` entries in SSH config (e.g. `Host *`) are skipped.

## Usage

```bash
./apt-herd.rb [options] [host1 host2 ...]
```

**Examples**

- Use config + SSH config hosts:  
  `./apt-herd.rb`
- Only specific hosts:  
  `./apt-herd.rb host1 host2`
- Dry run (no remote commands):  
  `./apt-herd.rb -n`
- Verbose (show apt output):  
  `./apt-herd.rb -v`
- Custom config file:  
  `./apt-herd.rb -c /path/to/apt-herd.yaml`

**Options**

| Option | Description |
|--------|-------------|
| `-u`, `--user USER` | SSH user (for hosts not in SSH config) |
| `-p`, `--port PORT` | SSH port |
| `-k`, `--key KEY` | SSH key path (repeatable) |
| `-t`, `--timeout SEC` | SSH timeout in seconds |
| `-n`, `--dry-run` | Print what would run, don’t run it |
| `-v`, `--verbose` | Show apt-get output per host |
| `-c`, `--config PATH` | Config file path |
| `--ssh-config` | Use hosts from `~/.ssh/config` |
| `-h`, `--help` | Show help |

Exit code is 0 if all hosts succeed, 1 if any fail (failed hosts are listed at the end).

## Scheduling (cron)

To run apt-herd automatically (e.g. every Monday at 01:00), add a cron job. Run from the repo directory so `apt-herd.yaml` is found, or use `-c /path/to/apt-herd.yaml`.

**Example: every Monday at 01:00**

```bash
# Edit your crontab
crontab -e
```

Add a line (replace `/path/to/apt-herd` with the directory containing `apt-herd.rb` and `apt-herd.yaml`):

```
0 1 * * 1 cd /path/to/apt-herd && ./apt-herd.rb
```

To log output to a file in the repo (user-writable, no root needed):

```
0 1 * * 1 cd /path/to/apt-herd && ./apt-herd.rb >> apt-herd.log 2>&1
```

Cron format: minute (0–59), hour (0–23), day of month, month, day of week (0=Sunday, 1=Monday, …). So `0 1 * * 1` = 01:00 on Mondays.
