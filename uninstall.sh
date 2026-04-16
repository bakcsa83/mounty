#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
MOUNTY="$INSTALL_DIR/mounty"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_USER_DIR/mounty-unlock.service"
NM_DISPATCHER="/etc/NetworkManager/dispatcher.d/50-mounty"

echo "Mounty - Uninstall"
echo "---"

# Remove all shares if mounty is available
if [[ -x "$MOUNTY" ]]; then
    shares=$("$MOUNTY" list 2>/dev/null | awk 'NR>4 && $1 != "" {print $1}') || true
    if [[ -n "$shares" ]]; then
        echo "Removing configured shares..."
        while IFS= read -r name; do
            "$MOUNTY" remove "$name" 2>/dev/null || warn "could not remove $name"
        done <<< "$shares"
    fi

    # Lock vault (unmounts tmpfs)
    "$MOUNTY" lock 2>/dev/null || true
fi

# Remove NetworkManager dispatcher
if [[ -f "$NM_DISPATCHER" ]]; then
    sudo rm "$NM_DISPATCHER"
    echo "Removed NetworkManager dispatcher"
fi

# Remove systemd user service
if [[ -f "$SERVICE_FILE" ]]; then
    systemctl --user disable mounty-unlock.service 2>/dev/null || true
    systemctl --user stop mounty-unlock.service 2>/dev/null || true
    rm "$SERVICE_FILE"
    systemctl --user daemon-reload
    echo "Removed mounty-unlock.service"
fi

# Remove mounty binary
if [[ -f "$MOUNTY" ]]; then
    rm "$MOUNTY"
    echo "Removed $MOUNTY"
fi

# Remove credential directory
if [[ -d "$HOME/.mounty" ]]; then
    rm -rf "$HOME/.mounty"
    echo "Removed ~/.mounty"
fi

# Remove mount directory (only if empty)
if [[ -d "$HOME/mnt" ]]; then
    if rmdir "$HOME/mnt" 2>/dev/null; then
        echo "Removed ~/mnt"
    else
        echo "warning: ~/mnt is not empty, kept"
    fi
fi

echo "---"
echo "Done. cifs-utils was not removed (may be used by other tools)."
