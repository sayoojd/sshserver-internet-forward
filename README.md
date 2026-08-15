# GPU server mirroring to Claude Code and Codex from a local workstation

This repository reproduces the local framework used to run Claude Code and
Codex against two SSH servers while keeping their files, shell commands,
accounts, sessions, and mount visibility separated.

Claude Code and Codex run on the workstation. Files are read and edited through
SSHFS at paths identical to the remote paths. Every Bash command is routed over
SSH to the server that owns the selected workspace.

## Fixed topology contract

The remote and local paths intentionally match:

| SSH alias | Local SSHFS target | Remote source |
| --- | --- | --- |
| `dep` | `/home/mauajama/Sayooj` | `/home/mauajama/Sayooj` |
| `dep` | `/mnt/DATA/mauajama/Sayooj` | `/mnt/DATA/mauajama/Sayooj` |
| `pranaysir` | `/home/mauajama/Sayooj_y` | `/home/mauajama/Sayooj_y` |
| `pranaysir` | `/data/mauajama/Sayooj_y` | `/data/mauajama/Sayooj_y` |

The workstation username and home directory are detected at installation and
launch time. The four mirrored project paths and the SSH aliases are fixed
because command routing depends on them being identical locally and remotely.

## What is reproduced

- Four independently supervised SSHFS mounts, all active concurrently.
- A health timer that checks and recovers each mount independently.
- `pranay-claude1`, `pranay-claude2`, `dep-claude1`, and `dep-claude2` with
  isolated Claude homes/settings as appropriate.
- `pranay-codex` and `dep-codex` with separate `CODEX_HOME` state.
- `claude2` as a second, fully local Claude account with isolated configuration
  and history but the normal workstation filesystem and shell.
- Cross-session auto memory disabled for every normal and isolated Claude and
  Codex profile. Existing memory files are retained but are neither loaded nor
  extended by new sessions.
- Private mount namespaces that hide the other server from each agent session.
- One-way mount propagation so running agents receive recovered SSHFS mounts
  without leaking their namespace-only overlays back to the workstation.
- Bash routing to the correct SSH host while preserving the absolute cwd.
- A narrowly validated permission hook for read-only `tail -f | grep` monitors.
- `/home/<local-user>/machines/dep` as a shortcut to the Dep home mount.
- Boot persistence through systemd user units and user lingering.

The repository deliberately does **not** contain SSH private keys, Claude login
tokens, Codex `auth.json`, session history, logs, caches, or state databases.
Authentication is recreated from the target workstation's own secure stores.

## Prerequisites

The supported workstation environment is Linux with systemd user services,
FUSE/SSHFS, and unprivileged user namespaces. On Ubuntu/Debian, install the OS
dependencies with:

```bash
sudo apt update
sudo apt install openssh-client sshfs fuse3 util-linux python3
```

Also install and authenticate the current Claude Code and Codex CLIs using
their official installers. Before continuing, these commands must work as the
normal workstation user:

```bash
claude --version
codex --version
test -f ~/.codex/config.toml
test -f ~/.codex/auth.json
test -x ~/.codex/packages/standalone/current/bin/codex
```

The Codex launchers intentionally execute the standalone ELF directly. The
normal `codex` command on this workstation is a Bash wrapper, and `/bin/bash`
is replaced by the SSH router inside the private namespace. Executing that
wrapper after the replacement would route the launcher itself to the server.

## 1. Configure SSH

Copy the relevant entries from
[`config/ssh-config.example`](config/ssh-config.example) into `~/.ssh/config`,
replace every `CHANGE_ME` value, and protect the file:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config ~/.ssh/CHANGE_ME_PRIVATE_KEY
```

Accept and verify each server's host key interactively once, then confirm that
key-based, non-interactive access works:

```bash
ssh dep true
ssh pranaysir true
ssh -o BatchMode=yes dep true
ssh -o BatchMode=yes pranaysir true
```

The remote account must be able to read and write the four remote directories
listed in the topology table. No server-side Claude or Codex installation is
required; only ordinary Bash and the project software are needed remotely.

## 2. Clone the private repository

```bash
git clone https://github.com/sayoojd/gpu-server-mirroring-to-claud-codex-from-local.git
cd gpu-server-mirroring-to-claud-codex-from-local
```

## 3. Prepare local mountpoints once

Creating the fixed top-level paths is the only privileged setup step:

```bash
sudo ./prepare-mountpoints.sh
```

The script refuses to alter an active mount and gives only the normal user
ownership of the four empty mountpoint directories. Do not run `install.sh`
with sudo.

## 4. Preflight and install

Run the non-mutating preflight first:

```bash
./install.sh --preflight
```

Every line should report `PASS`. Resolve any SSH, path, user-namespace, CLI, or
authentication failure before installing. Then run:

```bash
./install.sh
```

The installer:

1. Copies launchers and helpers to `~/bin`.
2. Creates isolated Claude homes and installs the permission JSON templates.
3. Creates namespace-only passwd views and SSH-key symlinks.
4. Copies global Codex config, auth, skills, and plugins into independent
   `~/.codex-dep` and `~/.codex-pranay` homes.
5. Installs, enables, and starts all systemd user mount units and the health
   timer.
6. Creates `~/machines/dep` and runs the post-install doctor.

Existing Claude settings are timestamp-backed-up before replacement. Existing
Codex homes are not overwritten, preserving their independent sessions and
later customizations.

If `~/bin` is not already in `PATH`, add this to the shell startup file:

```bash
export PATH="$HOME/bin:$PATH"
```

For mounts to start after reboot before the first login, lingering must be
enabled. The installer attempts this; if it prints a warning, run:

```bash
sudo loginctl enable-linger "$USER"
```

## 5. Authenticate isolated Claude accounts

Authentication is never copied into Git. Authenticate any launcher that does
not already have a valid session:

```bash
pranay-claude auth
pranay-claude2 auth
dep-claude1 auth
dep-claude2 auth
```

`pranay-claude` and `pranay-claude1` are the same primary launcher. The second
Pranay home and both Dep homes can hold independent Claude accounts.

The two Codex homes begin as independent copies of the already-authenticated
global `~/.codex` setup. If a copied credential later needs replacement, use:

```bash
dep-codex login
pranay-codex login
```

## Usage

```bash
# Claude Code
claude2                    # second local account; no SSH routing
pranay-claude1
pranay-claude2
dep-claude1
dep-claude2

# Codex
pranay-codex
dep-codex

# Resume histories (each home is independent)
pranay-claude1 --continue
dep-claude1 --continue
pranay-codex resume
dep-codex resume
```

### Second local Claude account

`claude2` is independent of the normal `claude` login. It uses
`~/.claude2` through Claude Code's `CLAUDE_CONFIG_DIR` mechanism while keeping
the normal `$HOME`, current working directory, local filesystem, and local
shell. It does not enter a mount namespace and never forwards commands over
SSH.

Authenticate it once with:

```bash
claude2 auth login
```

Thereafter, use `claude2`, `claude2 --continue`, and `claude2 --resume` in the
same way as the normal local `claude` command. The installer copies the normal
settings template into the second account but never copies credentials,
conversations, or runtime state.

### Cross-session memory isolation

All installed profiles disable automatic memory sharing between sessions:

- Claude settings use `autoMemoryEnabled: false` and
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. Custom launchers also export the
  environment variable as a non-project-overridable guard.
- Codex settings use both `memories.generate_memories = false` and
  `memories.use_memories = false`. The Dep and Pranay launchers repeat both as
  command-line overrides.

This applies to normal `claude`, local `claude2`, all four SSH-backed Claude
launchers, normal `codex`, `dep-codex`, and `pranay-codex`. It does not delete
previous memory files; disabling use prevents those files from being injected
into new sessions. Restart or resume an agent after installation so it loads
the new setting.

### Tool permission policy

All Claude profiles pre-approve `Bash(*)` and `Artifact`. The Artifact rule
allows Claude to publish HTML or Markdown pages to the account's private area
on claude.ai without another tool prompt. Publishing still uploads the selected
file to Anthropic-operated infrastructure; public sharing remains a separate
account-side action.

The four managed Dep and Pranay mount roots are also listed under
`permissions.additionalDirectories`, with matching absolute `Read(...)`
allow rules. This lets recognized file-reading shell commands such as `tail`,
`head`, `cat`, and `grep` monitor files on the data mounts even when the Claude
session started from the corresponding home-project mount.

All Codex profiles use `approval_policy = "never"` with
`sandbox_mode = "danger-full-access"`. The Dep and Pranay launchers repeat
those values as command-line overrides, and installation repairs them in each
Codex config. These settings allow shell execution without approval prompts;
they do not provide a Claude Artifact tool because Codex has no equivalent
Claude-specific publisher.

Starting a launcher outside its allowed roots moves it to that server's home
project root. Starting it inside either allowed root preserves the current
subdirectory. This also avoids stale-cwd failures after an SSHFS reconnect.

## Isolation behavior

Each launcher enters an unprivileged private mount namespace:

- Dep sessions see the two Dep mounts and cover both Pranay mounts with empty,
  read-only tmpfs overlays.
- Pranay sessions see the two Pranay mounts and similarly hide both Dep mounts.
- These overlays exist only inside that launcher process tree. They never
  unmount or hide paths from the host or another tmux session.
- The namespaces are recursive slaves of the host mount tree. Host-side SSHFS
  unmount/remount events therefore flow into already-running agents, while
  namespace changes cannot flow in the opposite direction. This prevents a
  recovered host mount from leaving a long-running agent attached to a stale
  `ENOTCONN` FUSE endpoint.
- The health timer preserves an active SSHFS process when a short read probe
  fails, allowing SSHFS's own reconnect loop to retain the original FUSE mount
  and every process cwd inside it. It replaces a mount only when the owning
  systemd service is genuinely inactive or failed.
- Launchers capture the canonical remote cwd before the agent starts. Shell
  routers use that stable value instead of calling `getcwd()` on a potentially
  detached FUSE cwd.
- If an SSHFS process genuinely dies, its systemd unit lazily detaches the dead
  endpoint before replacement; this avoids a busy mount blocking recovery.
- The shell router refuses execution unless cwd belongs to the selected
  server, then executes the command over the matching SSH alias.

Codex has two additional accommodations:

- Dedicated routers understand Codex's `bash -lc` invocation form.
- Shell snapshots are disabled at launch because a locally generated snapshot
  path cannot be sourced by the remote Bash process.

## Verification and operations

Run the complete check at any time:

```bash
framework-doctor
```

The doctor verifies both prerequisites for reconnect survival: a shared host
mount tree and launchers configured with one-way slave propagation. Sessions
started with an older private-propagation launcher must be exited and resumed
once; propagation mode cannot be retrofitted onto their detached mount trees.

Useful focused checks:

```bash
systemctl --user status \
  claude-mount-dep-home.service \
  claude-mount-dep-data.service \
  claude-mount-pranay-home.service \
  claude-mount-pranay-data.service \
  claude-mount-health.timer

findmnt /home/mauajama/Sayooj
findmnt /mnt/DATA/mauajama/Sayooj
findmnt /home/mauajama/Sayooj_y
findmnt /data/mauajama/Sayooj_y

dep-codex doctor --json
pranay-codex doctor --json
```

To recover immediately rather than waiting for the one-minute timer:

```bash
systemctl --user start claude-mount-health.service
```

To inspect service logs:

```bash
journalctl --user -u claude-mount-dep-home.service -n 100
journalctl --user -u claude-mount-pranay-home.service -n 100
```

## Updating or rebuilding

After pulling repository changes, rerun `./install.sh`. It is idempotent for
mount directories, account homes, Codex homes, units, and the Dep shortcut.

Claude JSON templates are redeployed, with changed files backed up first.
Codex isolated homes remain independent after their initial copy. To build a
fresh isolated Codex home from a newly changed global setup, move the existing
`~/.codex-dep` or `~/.codex-pranay` directory to a backup location and rerun
`init-server-codex`; do not delete a home if its sessions are still needed.

## Repository layout

| Path | Purpose |
| --- | --- |
| `install.sh` | Non-root preflight, deployment, services, and verification |
| `prepare-mountpoints.sh` | One-time privileged creation of fixed mount paths |
| `bin/*-claude*` | Claude namespace launchers and remote Bash routers |
| `bin/*-codex*` | Codex launchers, routers, isolated-home initializer, and memory guard |
| `bin/sshfs-mount` | PATH-independent foreground SSHFS service helper |
| `bin/framework-doctor` | Read-only reproducibility and health audit |
| `bin/check-claude-mounts` | Per-mount recovery used by the timer |
| `config/*.json` | Credential-free Claude settings templates |
| `config/ssh-config.example` | Credential-free SSH alias template |
| `systemd/` | Persistent user services and health timer |
| `tests/validate-repository.sh` | Static syntax, secret-hygiene, and portability checks |

Run the repository validation locally with:

```bash
./tests/validate-repository.sh
```

`proxy.py`, `proxy-on`, and `proxy-off` are retained as legacy utilities but
are not required or installed by the current direct-network framework.
