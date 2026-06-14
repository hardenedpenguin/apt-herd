# apt-herd

Run `apt update`, `full-upgrade`, `autoremove`, and `clean` across multiple Debian hosts over SSH.

## Requirements

- Ruby 2.6+
- SSH access to targets (`apt`, `sudo` on each host)
- **Ruby dev headers** on the machine running apt-herd (`ed25519` / `bcrypt_pbkdf` compile native extensions)

## Install

Debian ships versioned Ruby tools (`bundle3.3`, `gem3.3`). Match the suffix to `ruby --version`. System gem dirs need `sudo`; use `--path vendor/bundle` to install locally without it.

Install headers first (match your Ruby version, e.g. Ruby 3.3):

```bash
sudo apt install ruby3.3-dev
```

**Bundler**

```bash
sudo bundle3.3 install --gemfile=Gemfile.apt-herd
# or: bundle3.3 install --gemfile=Gemfile.apt-herd --path vendor/bundle
./apt-herd.rb
```

**Gems only**

```bash
sudo gem3.3 install net-ssh ed25519 bcrypt_pbkdf
./apt-herd.rb
```

```bash
chmod +x apt-herd.rb
```

## Config

Edit `apt-herd.yaml` beside the script (or pass `-c /path/to/apt-herd.yaml`).

- `use_ssh_config: true` — pull hosts from `~/.ssh/config` (wildcards skipped)
- `hosts` — extra hostnames; merged with SSH config when enabled
- `ssh` — optional `port`, `user`, `keys`, `timeout` for hosts not in SSH config

Per-host SSH user/port/keys come from `~/.ssh/config` when available; otherwise use `ssh` settings or `-u`.

## Usage

```bash
./apt-herd.rb [options] [host1 host2 ...]
```

Hosts: CLI args, `apt-herd.yaml`, and/or `~/.ssh/config` (see config above). With no args, uses config + SSH config.

```bash
./apt-herd.rb              # all configured hosts
./apt-herd.rb host1 host2  # specific hosts
./apt-herd.rb -n           # dry run
./apt-herd.rb -v           # show apt output
```

| Option | Description |
|--------|-------------|
| `-u USER` | SSH user (non–SSH-config hosts) |
| `-p PORT` | SSH port |
| `-k KEY` | SSH key (repeatable) |
| `-t SEC` | SSH timeout |
| `-n` | Dry run |
| `-v` | Verbose |
| `-c PATH` | Config file |
| `--ssh-config` | Use `~/.ssh/config` hosts |
| `-h` | Help |

Exit 0 on success; 1 if any host fails.

## Cron

Every Monday at 01:00, logging to the repo:

```
0 1 * * 1 cd /path/to/apt-herd && ./apt-herd.rb >> apt-herd.log 2>&1
```
