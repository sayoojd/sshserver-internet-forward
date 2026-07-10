#!/bin/bash
set -e

echo "=== Claude Jumpserver Proxy Installer ==="

# 1. Create bin directory
mkdir -p "$HOME/bin"

# 2. Copy scripts
cp bin/pranay-claude "$HOME/bin/pranay-claude"
cp bin/pranay-claude2 "$HOME/bin/pranay-claude2"
cp bin/gpu-shell-pranay "$HOME/bin/gpu-shell-pranay"
cp bin/mount-pranay "$HOME/bin/mount-pranay"
cp bin/proxy-on "$HOME/bin/proxy-on"
cp bin/proxy-off "$HOME/bin/proxy-off"

chmod +x "$HOME/bin/pranay-claude" \
         "$HOME/bin/pranay-claude2" \
         "$HOME/bin/gpu-shell-pranay" \
         "$HOME/bin/mount-pranay" \
         "$HOME/bin/proxy-on" \
         "$HOME/bin/proxy-off"

echo "✔ Copied scripts to $HOME/bin"

# 3. Create isolated home directory for second account
mkdir -p "$HOME/.pranay2"

# 4. Create isolated passwd file if it doesn't exist
if [ ! -f "$HOME/.pranay2/passwd" ]; then
    cp /etc/passwd "$HOME/.pranay2/passwd"
    sed -i "s|^root:x:0:0:root:/root:|root:x:0:0:root:$HOME/.pranay2:|g" "$HOME/.pranay2/passwd"
    sed -i "s|^root:x:0:0:root:/home/sayooj:|root:x:0:0:root:$HOME/.pranay2:|g" "$HOME/.pranay2/passwd"
    echo "✔ Configured isolated passwd file"
fi

# 5. Create symlink for SSH credentials if it doesn't exist
if [ ! -e "$HOME/.pranay2/.ssh" ]; then
    ln -s "$HOME/.ssh" "$HOME/.pranay2/.ssh"
    echo "✔ Created symlink for SSH credentials"
fi

# 6. Install systemd user service
mkdir -p "$HOME/.config/systemd/user"
cp systemd/mount-pranay.service "$HOME/.config/systemd/user/mount-pranay.service"

# Enable lingering so service runs at boot without active sessions
loginctl enable-linger "$(whoami)" || echo "⚠️  Could not enable linger automatically (requires loginctl permission)."

# Start and enable the mount service
systemctl --user daemon-reload
systemctl --user enable mount-pranay.service
systemctl --user start mount-pranay.service

echo "✔ Installed and started systemd automount service"
echo ""
echo "=== Installation Completed Successfully! ==="
echo "You can now run:"
echo "  - 'proxy-on' : To enable proxy forwarding mode"
echo "  - 'proxy-off': To disable proxy mode (default)"
echo "  - 'pranay-claude': Run Claude Code (account 1)"
echo "  - 'pranay-claude2': Run Claude Code (account 2)"
