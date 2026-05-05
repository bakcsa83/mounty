#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"

echo "Mounty - Install"
echo "---"

# Refuse to install for accounts whose name or home contain characters that
# could be unsafely templated into shell-evaluated config or sudoers entries.
if [[ -z "${USER:-}" || ! "$USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: refusing to install for username '${USER:-}'" >&2
    exit 1
fi
if [[ -z "${HOME:-}" || ! "$HOME" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "error: refusing to install for HOME '${HOME:-}'" >&2
    exit 1
fi

# Ensure ~/.local/bin exists and is in PATH
mkdir -p "$INSTALL_DIR"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "warning: $INSTALL_DIR is not in your PATH"
    echo "Add this to your ~/.bashrc or ~/.zshrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# Stop any existing installation before overwriting the binary
if [[ -x "$INSTALL_DIR/mounty" ]]; then
    first_line=$(head -1 "$INSTALL_DIR/mounty")
    if echo "$first_line" | grep -q "bash"; then
        echo "Replacing bash version with Python version..."
    else
        echo "Upgrading existing mounty installation..."
    fi
    systemctl --user stop mounty-unlock.service 2>/dev/null || true
    "$INSTALL_DIR/mounty" lock 2>/dev/null || true
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
PartOf=graphical-session.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/mounty unlock
RemainAfterExit=yes
ExecStop=%h/.local/bin/mounty lock

[Install]
WantedBy=graphical-session.target
EOF

# Install root-owned config + helper + sudoers drop-in for unattended ops.
# The systemd user service and the resume / NetworkManager hooks have no TTY,
# so without passwordless sudo `sudo mount` fails with "a terminal is required".
# sudo-rs forbids wildcards in sudoers args, so we route every privileged op
# through one helper script with internal validation.
#
# The helper is shipped verbatim — identity is read from /etc/mounty.conf at
# runtime, eliminating the prior installer-side sed substitution and its
# templating-injection surface.
HELPER_FILE="/usr/local/sbin/mounty-helper"
SUDOERS_FILE="/etc/sudoers.d/mounty"
CONFIG_FILE="/etc/mounty.conf"
CONFIG_TMP=$(mktemp)
SUDOERS_TMP=$(mktemp)
trap 'rm -f "$CONFIG_TMP" "$SUDOERS_TMP"' EXIT

cat > "$CONFIG_TMP" <<EOF
# Mounty configuration. Managed by install.sh; do not edit manually.
# /usr/local/sbin/mounty-helper reads this file to identify the user it
# serves, then resolves UID/GID/HOME via getent passwd.
$USER
EOF
sudo install -m 0644 -o root -g root "$CONFIG_TMP" "$CONFIG_FILE"
echo "Installed config at $CONFIG_FILE"

sudo install -m 0755 -o root -g root "$SCRIPT_DIR/mounty-helper" "$HELPER_FILE"
echo "Installed helper at $HELPER_FILE"

USER_UID_NUM=$(id -u)
cat > "$SUDOERS_TMP" <<EOF
# Mounty - passwordless sudo for the helper script.
# Managed by mounty install.sh / uninstall.sh - do not edit manually.
#
# Granted by numeric UID so the rule survives a username rename without
# requiring this file to be regenerated. The helper itself also compares
# SUDO_UID against the user's UID at runtime (defence in depth).
#${USER_UID_NUM} ALL=(root) NOPASSWD: $HELPER_FILE
EOF

if ! sudo visudo -cf "$SUDOERS_TMP" >/dev/null; then
    echo "error: generated sudoers file failed validation; not installing" >&2
    sudo visudo -cf "$SUDOERS_TMP" >&2 || true
    exit 1
fi
sudo install -m 0440 -o root -g root "$SUDOERS_TMP" "$SUDOERS_FILE"
echo "Installed sudoers drop-in at $SUDOERS_FILE"

systemctl --user daemon-reload
systemctl --user reset-failed mounty-unlock.service 2>/dev/null || true
systemctl --user enable --now mounty-unlock.service
echo "Installed and started mounty-unlock.service (auto-unlock at login)"

# Install auto-recovery hooks (NetworkManager dispatcher + systemd-sleep hook)
"$INSTALL_DIR/mounty" install-dispatcher

echo "---"
echo "Done. Run 'mounty help' to get started."
