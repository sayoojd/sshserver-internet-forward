#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

[ "$(id -u)" -ne 0 ] || {
    echo "Run ./install.sh as your normal workstation user, not with sudo." >&2
    exit 1
}

echo "=== GPU server mirroring setup ==="
echo "Running clean-machine preflight checks..."
"$SCRIPT_DIR/bin/framework-doctor" --pre-install
[ "${1:-}" != "--preflight" ] || exit 0

mkdir -p "$HOME/bin"
scripts=(
    claude2
    pranay-claude pranay-claude1 pranay-claude2
    dep-claude1 dep-claude2
    gpu-shell-pranay gpu-shell-dep
    pranay-codex dep-codex
    gpu-shell-codex-pranay gpu-shell-codex-dep
    mount-pranay mount-dep sshfs-mount check-claude-mounts
    claude-allow-log-monitor init-server-codex framework-doctor
)
for script_name in "${scripts[@]}"; do
    install -m 0755 "$SCRIPT_DIR/bin/$script_name" "$HOME/bin/$script_name"
done
echo "Installed launchers and helpers in $HOME/bin"

case ":$PATH:" in
    *":$HOME/bin:"*) ;;
    *) echo "WARNING: add $HOME/bin to PATH before using the launchers." >&2 ;;
esac

# Create isolated Claude homes and install permission templates. Authentication
# is deliberately not stored in the repository; each isolated account can be
# authenticated after installation.
account_homes=("$HOME/.pranay1" "$HOME/.pranay2" "$HOME/.dep1" "$HOME/.dep2")
mkdir -p "$HOME/.claude" "$HOME/.claude2"
chmod 0700 "$HOME/.claude2"
for account_home in "${account_homes[@]}"; do
    mkdir -p "$account_home/.claude"
    chmod 0700 "$account_home"
done

install_claude_settings() {
    local source=$1 target=$2
    if [ -f "$target" ] && ! cmp -s "$source" "$target"; then
        backup="$target.backup.$(date +%Y%m%d-%H%M%S)"
        cp -a "$target" "$backup"
        echo "Backed up existing settings to $backup"
    fi
    install -m 0600 "$source" "$target"
}

install_claude_settings "$SCRIPT_DIR/config/claude-settings-primary.json" "$HOME/.claude/settings.json"
install_claude_settings "$SCRIPT_DIR/config/claude-settings-primary.json" "$HOME/.claude2/settings.json"
install_claude_settings "$SCRIPT_DIR/config/claude-settings-secondary.json" "$HOME/.pranay2/.claude/settings.json"
install_claude_settings "$SCRIPT_DIR/config/claude-settings-primary.json" "$HOME/.dep1/.claude/settings.json"
install_claude_settings "$SCRIPT_DIR/config/claude-settings-secondary.json" "$HOME/.dep2/.claude/settings.json"

create_passwd_view() {
    local output=$1 root_home=$2
    cp /etc/passwd "$output"
    sed -i "s|^root:x:0:0:root:[^:]*:|root:x:0:0:root:$root_home:|" "$output"
    chmod 0600 "$output"
}

create_passwd_view "$HOME/.pranay1/passwd" "$HOME"
create_passwd_view "$HOME/.pranay2/passwd" "$HOME/.pranay2"
create_passwd_view "$HOME/.dep1/passwd" "$HOME/.dep1"
create_passwd_view "$HOME/.dep2/passwd" "$HOME/.dep2"

for account_home in "$HOME/.pranay2" "$HOME/.dep1" "$HOME/.dep2"; do
    [ -e "$account_home/.ssh" ] || ln -s "$HOME/.ssh" "$account_home/.ssh"
done

# CODEX_HOME is the supported isolation boundary. Copy the current global
# config/auth/skills/plugins once while keeping sessions and runtime state new.
GPU_MIRROR_LOCAL_HOME="$HOME" "$HOME/bin/init-server-codex"

mkdir -p "$HOME/.config/systemd/user"
units=(
    claude-mount-pranay-home.service
    claude-mount-pranay-data.service
    claude-mount-dep-home.service
    claude-mount-dep-data.service
    claude-mount-health.service
    claude-mount-health.timer
    mount-pranay.service
    mount-dep.service
)
for unit in "${units[@]}"; do
    install -m 0644 "$SCRIPT_DIR/systemd/$unit" "$HOME/.config/systemd/user/$unit"
done

mkdir -p "$HOME/machines"
shortcut="$HOME/machines/dep"
if [ ! -e "$shortcut" ] && [ ! -L "$shortcut" ]; then
    ln -s /home/mauajama/Sayooj "$shortcut"
elif [ ! -L "$shortcut" ] || [ "$(readlink "$shortcut")" != /home/mauajama/Sayooj ]; then
    echo "WARNING: $shortcut already exists and was left unchanged." >&2
fi

if ! loginctl enable-linger "$(id -un)" 2>/dev/null; then
    echo "WARNING: lingering was not enabled. For boot-before-login startup run:" >&2
    echo "  sudo loginctl enable-linger $(id -un)" >&2
fi

systemctl --user daemon-reload
systemctl --user disable --now mount-pranay.service mount-dep.service >/dev/null 2>&1 || true
systemctl --user enable --now claude-mount-pranay-home.service
systemctl --user enable --now claude-mount-pranay-data.service
systemctl --user enable --now claude-mount-dep-home.service
systemctl --user enable --now claude-mount-dep-data.service
systemctl --user enable --now claude-mount-health.timer

echo
echo "=== Verifying installed framework ==="
"$HOME/bin/framework-doctor"

echo
echo "Installation complete. Authenticate any Claude account that is not already signed in:"
echo "  claude2 auth login"
echo "  pranay-claude auth"
echo "  pranay-claude2 auth"
echo "  dep-claude1 auth"
echo "  dep-claude2 auth"
echo
echo "Launchers: claude2, pranay-claude[1|2], dep-claude[1|2], pranay-codex, dep-codex"
