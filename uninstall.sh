#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
MOUNTY="$INSTALL_DIR/mounty"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_USER_DIR/mounty-unlock.service"
NM_DISPATCHER="/etc/NetworkManager/dispatcher.d/50-mounty"
SLEEP_HOOK="/usr/lib/systemd/system-sleep/mounty"
SUDOERS_FILE="/etc/sudoers.d/mounty"
HELPER_FILE="/usr/local/sbin/mounty-helper"
CONFIG_FILE="/etc/mounty.conf"
CRED_DIR="$HOME/.mounty"
LIVE_DIR="$HOME/.mounty/live"
MNT_DIR="$HOME/mnt"
FSTAB="/etc/fstab"
FSTAB_BEGIN="# >>> mounty managed mounts - do not edit manually >>>"
FSTAB_END="# <<< mounty managed mounts <<<"

PURGE=false
if [[ "${1:-}" == "--purge" ]]; then
    PURGE=true
fi

echo "Mounty - Uninstall${PURGE:+ (purge)}"
echo "---"

# --- Raw helpers used by --purge when the binary is absent or broken ---

_list_shares_raw() {
    [[ -d "$CRED_DIR" ]] || return 0
    find "$CRED_DIR" -maxdepth 1 -name 'cred-*' -printf '%f\n' 2>/dev/null \
        | sed 's/^cred-//' | sort
}

_kwallet_remove_raw() {
    local name="$1"
    command -v dbus-send &>/dev/null || return 0
    local handle
    handle=$(dbus-send --session --dest=org.kde.kwalletd6 --print-reply \
        /modules/kwalletd6 org.kde.KWallet.open \
        string:kdewallet int64:0 string:mounty 2>/dev/null \
        | grep int32 | awk '{print $2}') || return 0
    [[ -z "$handle" || "$handle" == "-1" ]] && return 0
    dbus-send --session --dest=org.kde.kwalletd6 --print-reply \
        /modules/kwalletd6 org.kde.KWallet.removeEntry \
        int32:"$handle" string:mounty "string:cred-${name}" string:mounty \
        >/dev/null 2>&1 || true
}

_remove_share_raw() {
    local name="$1" mnt="$MNT_DIR/$1"
    mountpoint -q "$mnt" 2>/dev/null && { sudo umount "$mnt" 2>/dev/null || true; }
    local unit
    unit=$(systemd-escape -p "$mnt" 2>/dev/null).automount
    sudo systemctl stop "$unit" 2>/dev/null || true
    sudo sed -i "/# mounty:${name}$/d" "$FSTAB" 2>/dev/null || true
    _kwallet_remove_raw "$name"
    rm -f "$CRED_DIR/cred-$name" "$LIVE_DIR/cred-$name"
    rmdir "$mnt" 2>/dev/null || true
    echo "Removed share: $name"
}

_fstab_section_cleanup() {
    grep -qF "$FSTAB_BEGIN" "$FSTAB" 2>/dev/null || return 0
    local content
    content=$(sudo sed -n "/^${FSTAB_BEGIN}$/,/^${FSTAB_END}$/p" "$FSTAB" \
        | grep -v '^#' | grep -v '^$' || true)
    if [[ -z "$content" ]]; then
        sudo sed -i "/^${FSTAB_BEGIN}$/,/^${FSTAB_END}$/d" "$FSTAB"
        sudo sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$FSTAB"
        echo "Removed mounty fstab section"
    fi
}

# --- Stop running services ---

systemctl --user stop mounty-unlock.service 2>/dev/null || true
if [[ -x "$MOUNTY" ]]; then
    "$MOUNTY" lock 2>/dev/null || true
elif mountpoint -q "$LIVE_DIR" 2>/dev/null; then
    sudo umount "$LIVE_DIR" 2>/dev/null || true
fi

# --- Purge: remove shares and all user data ---

if $PURGE; then
    if [[ -x "$MOUNTY" ]]; then
        shares=$("$MOUNTY" list 2>/dev/null | awk 'NR>4 && $1 != "" {print $1}') || true
        if [[ -n "$shares" ]]; then
            echo "Removing configured shares..."
            while IFS= read -r name; do
                "$MOUNTY" remove "$name" 2>/dev/null || echo "warning: could not remove $name" >&2
            done <<< "$shares"
        fi
    else
        shares=$(_list_shares_raw)
        if [[ -n "$shares" ]]; then
            echo "Binary not found, cleaning up shares directly..."
            while IFS= read -r name; do
                _remove_share_raw "$name"
            done <<< "$shares"
        fi
        _fstab_section_cleanup
        sudo systemctl daemon-reload 2>/dev/null || true
    fi

    if [[ -d "$CRED_DIR" ]]; then
        rm -rf "$CRED_DIR"
        echo "Removed ~/.mounty"
    fi

    if [[ -d "$MNT_DIR" ]]; then
        if rmdir "$MNT_DIR" 2>/dev/null; then
            echo "Removed ~/mnt"
        else
            echo "warning: ~/mnt is not empty, kept"
        fi
    fi
fi

# --- Remove system integration ---

if [[ -f "$NM_DISPATCHER" ]]; then
    sudo rm "$NM_DISPATCHER"
    echo "Removed NetworkManager dispatcher"
fi

if [[ -f "$SLEEP_HOOK" ]]; then
    sudo rm "$SLEEP_HOOK"
    echo "Removed systemd-sleep hook"
fi

if [[ -f "$SUDOERS_FILE" ]]; then
    sudo rm "$SUDOERS_FILE"
    echo "Removed $SUDOERS_FILE"
fi

if [[ -f "$HELPER_FILE" ]]; then
    sudo rm "$HELPER_FILE"
    echo "Removed $HELPER_FILE"
fi

if [[ -f "$CONFIG_FILE" ]]; then
    sudo rm "$CONFIG_FILE"
    echo "Removed $CONFIG_FILE"
fi

if [[ -f "$SERVICE_FILE" ]]; then
    systemctl --user disable mounty-unlock.service 2>/dev/null || true
    rm "$SERVICE_FILE"
    systemctl --user daemon-reload
    echo "Removed mounty-unlock.service"
fi

if [[ -f "$MOUNTY" ]]; then
    rm "$MOUNTY"
    echo "Removed $MOUNTY"
fi

echo "---"
if $PURGE; then
    echo "Done. All shares, credentials, and mounty files removed."
else
    echo "Done. Share configuration preserved. To also remove shares and credentials, run: uninstall.sh --purge"
fi
