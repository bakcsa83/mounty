# Mounty - Samba/CIFS Share Manager for KDE Plasma

A CLI tool for **KDE Plasma** desktops (Kubuntu, KDE Neon, Fedora KDE, etc.) that mounts Samba shares using kernel CIFS. Mounts behave like Windows mapped network drives — real filesystem paths visible to all applications.

Passwords are stored in **KDE Wallet** — live credentials exist only in RAM (tmpfs), never on disk.

## Requirements

- KDE Plasma desktop (for KDE Wallet integration)
- `cifs-utils` (installed automatically)
- `smbclient` (installed automatically when using `browse`)
- `dbus-send` (ships with dbus, present on virtually all Linux desktops)
- systemd

## Install

```bash
./install.sh
```

This installs the `mounty` command to `~/.local/bin/`, installs `cifs-utils`, creates the required directories, enables a systemd user service for auto-unlock at login, and installs a NetworkManager dispatcher for automatic recovery after VPN/network changes.

## Uninstall

```bash
./uninstall.sh
```

This removes all configured shares, the systemd service, the NetworkManager dispatcher, the mounty binary, and credential storage. `cifs-utils` is left installed.

## How it works

```
~/.mounty/
  cred-<name>        # username + domain only (no password)
  live/              # tmpfs (RAM) — full credentials with passwords
    cred-<name>      # written from KDE Wallet on unlock, gone on lock/reboot

KDE Wallet
  mounty/cred-<name> # passwords stored here
```

1. `mounty unlock` mounts a tmpfs at `~/.mounty/live/` and populates credential files from KDE Wallet
2. fstab entries point to `~/.mounty/live/cred-<name>` — only works while unlocked
3. `mounty lock` unmounts the tmpfs — all passwords vanish from RAM
4. On reboot, the tmpfs is gone — run `mounty unlock` again (or automate at login)

## Usage

### Unlock / Lock

```bash
mounty unlock    # load passwords from KDE Wallet into RAM
mounty lock      # unmount all shares, clear credentials from RAM
```

### Browse a server

```bash
mounty browse 192.168.1.10
```

Connects to the server, lists available shares, and lets you pick one to add:

```
:: browsing //192.168.1.10 ...
:: negotiated SMB 3.1.1

  #    SHARE                          COMMENT
  --   -----                          -------
  1    Data                           Main storage
  2    Photos                         Photo archive
  3    Backups                        Backup share

Select share to add [1-3, or q to quit]: 1
:: selected: Data
:: password stored in KDE Wallet
```

The SMB protocol version is detected automatically from the server negotiation.

### Add a share manually

```bash
mounty add nas
```

Interactive prompts ask for server, share name, username, and password. The password goes straight to KDE Wallet.

### Mount / Unmount

```bash
mounty mount nas        # mount a specific share
mounty unmount nas      # unmount a specific share
mounty mount --all      # mount all configured shares
mounty unmount --all    # unmount all
```

With automount enabled, shares mount automatically when you access `~/mnt/<name>` — manual mounting is optional.

### List shares

```bash
mounty list
```

```
Vault: unlocked

NAME                 STATUS     MOUNT POINT
----                 ------     -----------
nas                  mounted    /home/user/mnt/nas
office               unmounted  /home/user/mnt/office
```

### Detailed status

```bash
mounty status nas
```

```
Share: nas
  Mount point:  /home/user/mnt/nas
  Config:       /home/user/.mounty/cred-nas
  Live creds:   /home/user/.mounty/live/cred-nas (ready)
  Wallet:       mounty/cred-nas
  Remote:       //192.168.1.10/data
  SMB version:  3.1.1
  User:         NAS\user1
  Status:       MOUNTED
```

### Edit a share

```bash
mounty edit nas
```

Re-prompts for all fields, keeping current values as defaults. Password is read from KDE Wallet if unchanged.

### Remove a share

```bash
mounty remove nas
```

Unmounts, removes the fstab entry, credential files, wallet entry, and mount point.

### Recover after VPN / network changes

```bash
mounty reconnect
```

Resets failed automount units, unlocks the vault if locked, and lazy-unmounts stale mounts. Run this if shares stop working after a VPN connect/disconnect cycle.

With the NetworkManager dispatcher installed (done automatically by `install.sh`), this happens automatically on network changes. To manage the dispatcher manually:

```bash
mounty install-dispatcher    # install auto-recovery hook
mounty remove-dispatcher     # remove it
```

## fstab

All entries are managed inside a marked section:

```
# >>> mounty managed mounts - do not edit manually >>>
//nas/data /home/user/mnt/nas cifs credentials=/home/user/.mounty/live/cred-nas,... # mounty:nas
# <<< mounty managed mounts <<<
```

The section is created on first `mounty add` and removed when the last share is deleted.

## Mount options

| Option | Purpose |
|--------|---------|
| `credentials=` | Points to live (tmpfs) credential file |
| `vers=` | Auto-detected SMB version |
| `uid/gid` | Local file ownership |
| `file_mode=0644` | File permissions for proper application access |
| `dir_mode=0755` | Directory permissions for proper application access |
| `_netdev` | Wait for network before mounting |
| `x-systemd.automount` | Mount on first access |
| `x-systemd.idle-timeout=5min` | Unmount when idle |
| `nofail` | Boot even if server is unavailable |

## Auto-unlock at login

The installer sets up a systemd user service (`mounty-unlock.service`) that automatically runs `mounty unlock` when you log into your KDE Plasma session, and `mounty lock` on logout. KDE Wallet is already unlocked via PAM at that point, so the credentials flow seamlessly.

To check the service status:

```bash
systemctl --user status mounty-unlock.service
```

## Dolphin integration

Open `~/mnt/<name>` in Dolphin, then right-click the folder in the sidebar and select **Add to Places**. The share now appears as a bookmark like a normal folder.

## smb:// vs kernel CIFS

Dolphin's `smb://` mounts use KIO, which works well for casual file browsing. Kernel CIFS mounts via mounty are an alternative that provides real filesystem paths accessible to all applications — Dolphin, Konsole, IDEs, scripts, and containers.
