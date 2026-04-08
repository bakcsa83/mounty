# Mounty - Samba/CIFS Share Manager

A CLI tool for mounting Samba shares on Linux using kernel CIFS instead of GVFS.
Avoids the common issues with `smb://` mounts in Dolphin (disconnects, apps not seeing paths, poor performance).

Shares behave like Windows mapped network drives — stable, visible to all apps, independent credentials per mount.

## Install

```bash
./install.sh
```

This installs the `mounty` command to `~/.local/bin/`, installs `cifs-utils`, and creates the required directories.

## Usage

### Add a share

```bash
mounty add nas
```

Interactive prompts ask for server, share name, username, password, domain, and SMB version.

This creates:
- Credential file at `~/.mounty/cred-nas` (mode 600)
- Mount point at `~/mnt/nas`
- fstab entry with `x-systemd.automount` (auto-mounts on access)

### Browse a server

```bash
mounty browse 192.168.1.10
```

Connects to the server (with optional credentials), lists available shares, and lets you pick one to add:

```
:: browsing //192.168.1.10 ...

  #    SHARE                          COMMENT
  --   -----                          -------
  1    Data                           Main storage
  2    Photos                         Photo archive
  3    Backups                        Backup share

Select share to add [1-3, or q to quit]: 1
:: selected: Data
Mount name [data]:
```

After selecting, it reuses your browse credentials and sets up the share — same result as `mounty add`.

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
  Credentials:  /home/user/.mounty/cred-nas
  Remote:       //192.168.1.10/data
  SMB version:  3.1.1
  User:         NAS\user1
  Status:       MOUNTED
```

### Edit a share

```bash
mounty edit nas
```

Re-prompts for all fields, keeping current values as defaults. Updates credentials and fstab entry.

### Remove a share

```bash
mounty remove nas
```

Unmounts, removes the fstab entry, credential file, and mount point.

## File layout

```
~/.mounty/
  cred-<name>        # credential files (chmod 600)

~/mnt/
  <name>/            # mount points

/etc/fstab           # entries inside a managed section
```

All fstab entries are kept inside a clearly marked section:

```
# >>> mounty managed mounts - do not edit manually >>>
//nas/data /home/user/mnt/nas cifs credentials=... # mounty:nas
//server/projects /home/user/mnt/office cifs credentials=... # mounty:office
# <<< mounty managed mounts <<<
```

The section is created automatically on first `mounty add` and removed when the last share is deleted.

## Mount options

Each share is configured with these defaults:

| Option | Purpose |
|--------|---------|
| `credentials=` | Per-share credential file |
| `vers=3.1.1` | Modern SMB protocol version |
| `uid/gid` | Local file ownership |
| `_netdev` | Wait for network before mounting |
| `x-systemd.automount` | Mount on first access |
| `x-systemd.idle-timeout=5min` | Unmount when idle |
| `nofail` | Boot even if server is unavailable |

## Dolphin integration

Open `~/mnt/<name>` in Dolphin, then right-click the folder in the sidebar and select **Add to Places**. The share now appears as a bookmark like a normal folder.

## Why not smb:// ?

`smb://` URIs use GVFS which:
- Randomly disconnects
- Is invisible to many applications (IDEs, CLI tools, containers)
- Has poor performance
- Causes authentication issues

Kernel CIFS mounts behave like real filesystems and work with everything.
