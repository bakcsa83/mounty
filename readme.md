# Mounty - Samba/CIFS Share Manager for KDE Plasma

A CLI tool for **KDE Plasma** desktops (Kubuntu, KDE Neon, Fedora KDE, etc.) that mounts Samba shares using kernel CIFS. Mounts behave like Windows mapped network drives — real filesystem paths visible to all applications.

Passwords are stored in **KDE Wallet** — live credentials exist only in RAM (tmpfs), never on disk.

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

## Install

```bash
./install.sh
```

This installs the `mounty` command to `~/.local/bin/`, installs `cifs-utils`, creates the required directories, enables a systemd user service for auto-unlock at login, installs a NetworkManager dispatcher and a systemd-sleep hook for automatic recovery, and installs the privileged helper (`/usr/local/sbin/mounty-helper`) plus its sudoers drop-in. See [Security model](#security-model) for what runs as root and why.

## Uninstall

```bash
./uninstall.sh           # keep shares, remove the binary + helper + hooks
./uninstall.sh --purge   # also remove all shares, fstab entries, and KDE Wallet entries
```

The default uninstall stops the services and removes the mounty binary, the helper, the sudoers drop-in, the systemd user service, and the NetworkManager / sleep hooks. Configured shares, credential files, and KDE Wallet entries are preserved so a later reinstall picks them back up. `--purge` additionally tears down every share and removes the on-disk credential files.

`cifs-utils` is left installed in either case.

## Requirements

- KDE Plasma desktop (for KDE Wallet integration)
- `cifs-utils` (installed automatically)
- `smbclient` (installed automatically when using `browse`)
- `dbus-send` (ships with dbus, present on virtually all Linux desktops)
- systemd

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

## Security model

Mounty needs root for `mount` / `umount` and for `systemctl daemon-reload` / `automount` actions. The systemd user service and the resume / NetworkManager hooks run without a TTY, so prompting for sudo each time isn't possible — and sudo-rs (Ubuntu's default since 26.04) forbids wildcards in sudoers command arguments, ruling out the traditional "tight rule with `*` in the args" approach. Mounty solves this with one root-owned helper plus a single tightly scoped NOPASSWD grant.

### `/usr/local/sbin/mounty-helper`

A small POSIX-sh script installed root-owned (mode 0755). Every privileged op the Python wrapper needs is dispatched as one of six fixed verbs: `mount-tmpfs`, `umount-tmpfs`, `mount-share`, `umount-share`, `daemon-reload`, `automount`. Anything outside that set is rejected.

What the helper does on every invocation:

- Reads the owning user's name from `/etc/mounty.conf` at runtime; UID, GID, and HOME are looked up via `getent passwd`. Nothing user-controlled is ever templated into the script — the helper file is shipped verbatim.
- Compares `$SUDO_UID` against the configured user's UID and refuses on mismatch.
- Resolves every mount/umount target through `realpath` and refuses if the path (or any parent) is a symlink. Closes the "swap `~/.mounty/live` for a symlink to `/etc`" attack against unprivileged code running as the user.
- Validates every share name against `[A-Za-z0-9._-]+` (no `/`, no `.` / `..`, no shell metacharacters).
- Acquires `/run/mounty.lock` via `flock` so the systemd user service, NetworkManager dispatcher, sleep hook, and manual CLI cannot race each other into `mount` or `systemctl`.
- Logs every invocation to syslog (`auth.info`, tag `mounty-helper`). Inspect with `journalctl -t mounty-helper`.

### `/etc/sudoers.d/mounty`

One line:

```
#1000 ALL=(root) NOPASSWD: /usr/local/sbin/mounty-helper
```

The grant is by numeric UID (`#UID`) rather than username so it survives a rename without regeneration. The helper itself is the trust boundary; sudo just removes the password prompt for that one path.

### `/etc/mounty.conf`

Root-owned, mode 0644. Contains the username, nothing else. Read on every helper invocation, so UID/GID/HOME drift is self-correcting.

### Python-side input validation

The `mounty` Python wrapper validates every value that ends up in `/etc/fstab` or in a credential file:

| Field | Pattern |
|-------|---------|
| `name`, `server` | `[A-Za-z0-9._-]+` |
| `share` | `[A-Za-z0-9._$-]+` (allows `$` for admin shares like `C$`) |
| credential fields | rejects `\n`, `\r`, `\0` |

A crafted value cannot inject a second fstab entry or a stray `password=` line into the cred file (which `mount.cifs` would otherwise honour over the real one).

The NetworkManager dispatcher and systemd-sleep hook scripts are generated with `shlex.quote` for any interpolated value, so a `HOME` path with a single quote in it cannot escape the generated `/bin/sh` script.

### Credentials at rest

Passwords live only in:

1. **KDE Wallet** — encrypted, unlocked via PAM at login.
2. **`~/.mounty/live/cred-<name>`** — on a tmpfs mounted with `mode=700,size=1M`; gone on lock or reboot.

The on-disk `~/.mounty/cred-<name>` files contain only `username=` and `domain=` — no password.

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
