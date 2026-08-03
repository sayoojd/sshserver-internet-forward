#!/bin/bash
set -e

echo "=== Claude Jumpserver Setup Installer ==="

# 1. Create bin directory
mkdir -p "$HOME/bin"

# 2. Copy scripts
cp bin/pranay-claude "$HOME/bin/pranay-claude"
cp bin/pranay-claude1 "$HOME/bin/pranay-claude1"
cp bin/pranay-claude2 "$HOME/bin/pranay-claude2"
cp bin/gpu-shell-pranay "$HOME/bin/gpu-shell-pranay"
cp bin/mount-pranay "$HOME/bin/mount-pranay"
cp bin/dep-claude1 "$HOME/bin/dep-claude1"
cp bin/dep-claude2 "$HOME/bin/dep-claude2"
cp bin/gpu-shell-dep "$HOME/bin/gpu-shell-dep"
cp bin/mount-dep "$HOME/bin/mount-dep"
cp bin/check-claude-mounts "$HOME/bin/check-claude-mounts"
cp bin/claude-allow-log-monitor "$HOME/bin/claude-allow-log-monitor"
cp bin/dep-codex "$HOME/bin/dep-codex"
cp bin/pranay-codex "$HOME/bin/pranay-codex"
cp bin/gpu-shell-codex-dep "$HOME/bin/gpu-shell-codex-dep"
cp bin/gpu-shell-codex-pranay "$HOME/bin/gpu-shell-codex-pranay"
cp bin/init-server-codex "$HOME/bin/init-server-codex"

chmod +x "$HOME/bin/pranay-claude" \
         "$HOME/bin/pranay-claude1" \
         "$HOME/bin/pranay-claude2" \
         "$HOME/bin/gpu-shell-pranay" \
         "$HOME/bin/mount-pranay" \
         "$HOME/bin/dep-claude1" \
         "$HOME/bin/dep-claude2" \
         "$HOME/bin/gpu-shell-dep" \
         "$HOME/bin/mount-dep" \
         "$HOME/bin/check-claude-mounts" \
         "$HOME/bin/claude-allow-log-monitor" \
         "$HOME/bin/dep-codex" \
         "$HOME/bin/pranay-codex" \
         "$HOME/bin/gpu-shell-codex-dep" \
         "$HOME/bin/gpu-shell-codex-pranay" \
         "$HOME/bin/init-server-codex"

echo "✔ Copied scripts to $HOME/bin"

# Codex officially supports CODEX_HOME for isolated configuration and state.
# Copy setup/auth/skills/plugins once; keep logs and sessions independent.
"$HOME/bin/init-server-codex"

# 3. Create isolated home directories for accounts
mkdir -p "$HOME/.pranay1"
mkdir -p "$HOME/.pranay2"
mkdir -p "$HOME/.dep1"
mkdir -p "$HOME/.dep2"
chmod 700 "$HOME/.pranay1" "$HOME/.pranay2" \
          "$HOME/.dep1" "$HOME/.dep2"
mkdir -p "$HOME/.claude" "$HOME/.pranay2/.claude" \
         "$HOME/.dep1/.claude" "$HOME/.dep2/.claude"

# Use the permission allowlists from inst:~/Sayooj/tools/claude rather than
# bypassPermissions, which Claude refuses inside the root-mapped namespace.
cp config/claude-settings-primary.json "$HOME/.claude/settings.json"
cp config/claude-settings-secondary.json "$HOME/.pranay2/.claude/settings.json"
cp config/claude-settings-primary.json "$HOME/.dep1/.claude/settings.json"
cp config/claude-settings-secondary.json "$HOME/.dep2/.claude/settings.json"
chmod 600 "$HOME/.claude/settings.json" \
          "$HOME/.pranay2/.claude/settings.json" \
          "$HOME/.dep1/.claude/settings.json" \
          "$HOME/.dep2/.claude/settings.json"

# 4. Create isolated passwd files for account 1 and account 2
if [ ! -f "$HOME/.pranay1/passwd" ]; then
    cp /etc/passwd "$HOME/.pranay1/passwd"
    sed -i "s|^root:x:0:0:root:/root:|root:x:0:0:root:$HOME:|g" "$HOME/.pranay1/passwd"
    sed -i "s|^root:x:0:0:root:/home/sayooj:|root:x:0:0:root:$HOME:|g" "$HOME/.pranay1/passwd"
    echo "✔ Configured isolated passwd file for Account 1"
fi

for account_home in "$HOME/.dep1" "$HOME/.dep2"; do
    if [ ! -f "$account_home/passwd" ]; then
        cp /etc/passwd "$account_home/passwd"
        sed -i "s|^root:x:0:0:root:/root:|root:x:0:0:root:$account_home:|g" "$account_home/passwd"
        echo "✔ Configured passwd file for $account_home"
    fi

    if [ ! -e "$account_home/.ssh" ]; then
        ln -s "$HOME/.ssh" "$account_home/.ssh"
    fi
done

if [ ! -f "$HOME/.pranay2/passwd" ]; then
    cp /etc/passwd "$HOME/.pranay2/passwd"
    sed -i "s|^root:x:0:0:root:/root:|root:x:0:0:root:$HOME/.pranay2:|g" "$HOME/.pranay2/passwd"
    sed -i "s|^root:x:0:0:root:/home/sayooj:|root:x:0:0:root:$HOME/.pranay2:|g" "$HOME/.pranay2/passwd"
    echo "✔ Configured isolated passwd file for Account 2"
fi

# 5. Create symlink for SSH credentials for account 2 if it doesn't exist
if [ ! -e "$HOME/.pranay2/.ssh" ]; then
    ln -s "$HOME/.ssh" "$HOME/.pranay2/.ssh"
    echo "✔ Created symlink for SSH credentials for Account 2"
fi

# 6. Install systemd user service
mkdir -p "$HOME/.config/systemd/user"
cp systemd/mount-pranay.service "$HOME/.config/systemd/user/mount-pranay.service"
cp systemd/mount-dep.service "$HOME/.config/systemd/user/mount-dep.service"
cp systemd/claude-mount-health.service "$HOME/.config/systemd/user/claude-mount-health.service"
cp systemd/claude-mount-health.timer "$HOME/.config/systemd/user/claude-mount-health.timer"
cp systemd/claude-mount-pranay-home.service "$HOME/.config/systemd/user/claude-mount-pranay-home.service"
cp systemd/claude-mount-pranay-data.service "$HOME/.config/systemd/user/claude-mount-pranay-data.service"
cp systemd/claude-mount-dep-home.service "$HOME/.config/systemd/user/claude-mount-dep-home.service"
cp systemd/claude-mount-dep-data.service "$HOME/.config/systemd/user/claude-mount-dep-data.service"

# Enable lingering so service runs at boot without active sessions
loginctl enable-linger "$(whoami)" 2>/dev/null || echo "⚠️ Could not enable linger automatically (requires loginctl permission)."

# Start and enable the mount service
systemctl --user daemon-reload || true
systemctl --user disable --now mount-pranay.service mount-dep.service || true
systemctl --user enable claude-mount-pranay-home.service || true
systemctl --user enable claude-mount-pranay-data.service || true
systemctl --user enable claude-mount-dep-home.service || true
systemctl --user enable claude-mount-dep-data.service || true
systemctl --user enable claude-mount-health.timer || true
systemctl --user start claude-mount-pranay-home.service || true
systemctl --user start claude-mount-pranay-data.service || true
systemctl --user start claude-mount-dep-home.service || true
systemctl --user start claude-mount-dep-data.service || true
systemctl --user start claude-mount-health.timer || true

echo "✔ Installed systemd automount service"
echo ""
echo "=== Installation Completed Successfully! ==="
echo "You can now run:"
echo "  - 'pranay-claude': Run Claude Code (account 1)"
echo "  - 'pranay-claude1': Alias for pranay-claude"
echo "  - 'pranay-claude2': Run Claude Code (account 2)"
echo "  - 'dep-claude1': Run Claude Code on dep (account 1)"
echo "  - 'dep-claude2': Run Claude Code on dep (account 2)"
echo "  - 'pranay-codex': Run isolated Codex for pranaysir"
echo "  - 'dep-codex': Run isolated Codex for dep"
