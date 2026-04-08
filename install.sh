#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"

echo "Mounty - Install"
echo "---"

# Ensure ~/.local/bin exists and is in PATH
mkdir -p "$INSTALL_DIR"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "warning: $INSTALL_DIR is not in your PATH"
    echo "Add this to your ~/.bashrc or ~/.zshrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# Install cifs-utils if missing
if ! command -v mount.cifs &>/dev/null; then
    echo "Installing cifs-utils..."
    sudo apt install -y cifs-utils
else
    echo "cifs-utils is already installed"
fi

# Copy script
cp "$SCRIPT_DIR/mounty" "$INSTALL_DIR/mounty"
chmod +x "$INSTALL_DIR/mounty"
echo "Installed mounty to $INSTALL_DIR/mounty"

# Create directories
mkdir -p "$HOME/.mounty"
mkdir -p "$HOME/mnt"
echo "Created ~/.mounty and ~/mnt directories"

# Install systemd user service for auto-unlock at login
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_USER_DIR/mounty-unlock.service"
mkdir -p "$SYSTEMD_USER_DIR"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Mounty - unlock SMB credentials from KDE Wallet
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/mounty unlock
RemainAfterExit=yes
ExecStop=%h/.local/bin/mounty lock

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload
systemctl --user enable mounty-unlock.service
echo "Installed and enabled mounty-unlock.service (auto-unlock at login)"

echo "---"
echo "Done. Run 'mounty help' to get started."
