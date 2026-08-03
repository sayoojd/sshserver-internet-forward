# GPU server mirroring to Claude Code and Codex from a local workstation

Claude Code runs on the local workstation, reads and edits remote files through
SSHFS, and sends Bash commands to the server that owns the current project.

## Mirrored mounts

| Server | Local and remote path |
| --- | --- |
| `dep` | `/home/mauajama/Sayooj` |
| `dep` | `/mnt/DATA/mauajama/Sayooj` |
| `pranaysir` | `/home/mauajama/Sayooj_y` |
| `pranaysir` | `/data/mauajama/Sayooj_y` |

`/home/mauajama` and `/data/mauajama` are ordinary local parent directories.
The four project directories are independent SSHFS mounts and can remain active
at the same time.

`/home/sayooj/machines/dep` is a local symlink to `/home/mauajama/Sayooj`.
The older `sshfs-dep.service` whole-home mount is disabled, avoiding a second
connection and a duplicate view of the same Dep files.

## Claude launchers

- `pranay-claude` or `pranay-claude1`: primary Pranay account
- `pranay-claude2`: isolated secondary Pranay account
- `dep-claude1`: isolated Dep account 1
- `dep-claude2`: isolated Dep account 2

Each launcher uses a private mount namespace. Pranay launchers cover the Dep
mounts with read-only empty filesystems, while Dep launchers similarly cover the
Pranay mounts. These namespace-only mounts do not affect the host or concurrent
Claude sessions.

Launchers started outside their server's approved roots enter that server's home
project automatically. Their explicit settings files use the permission
allowlists from `inst:~/Sayooj/tools/claude`; they do not use bypassPermissions.

The corresponding shell wrapper also rejects commands when the current working
directory is outside that server's two approved roots. This prevents a Claude
session from reading through one server's SSHFS mount while executing commands
on the other server.

## Codex launchers

- `pranay-codex`: isolated Codex environment for `pranaysir`
- `dep-codex`: isolated Codex environment for `dep`

Codex uses its supported `CODEX_HOME` mechanism: `/home/sayooj/.codex-pranay`
and `/home/sayooj/.codex-dep` are independent copies of the workstation's
global config, authentication, skills, and plugins. Session history, logs,
caches, and mutable state are separate. Both launchers reuse the global Codex
executable, so its large package is not duplicated and global Codex upgrades
apply to both launchers.

The Codex launchers have dedicated SSH shell routers that understand Codex's
`bash -lc` command form. They disable shell snapshots at launch because the
generated files exist locally and cannot be sourced by the remote shell. Server
mount visibility and working-directory isolation are the same as for the Claude
launchers.

## Services

- Four `claude-mount-<server>-<home|data>.service` units independently own the
  four SSHFS processes. Recovering one mount never replaces its sibling mount.
- `claude-mount-health.timer` checks all four paths every minute and repairs a
  missing or stale SSHFS mount.

The mount services retry boot-time failures, and user lingering starts them even
before an interactive login. Run `./install.sh` to deploy the scripts, account
directories, and service units.
