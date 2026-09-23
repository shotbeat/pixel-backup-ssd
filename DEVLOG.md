# Pixel Backup SSD — External SSD Setup (Pixel 1 / Pixel XL)

> **What this is:** Full documentation of the setup that mounts a 1 TB external SSD into a Google Pixel 1's
> internal storage so Google Photos backs up photos/videos at original quality (free unlimited perk of Pixel 1).
> Everything was done over `adb` from a Mac. All "buttons" are home-screen widgets (Termux:Widget) that run
> root shell scripts — no terminal typing needed.
>
> **Date documented:** 2026-08-25

> [!WARNING]
> **Use at your own risk.** This is experimental software for **rooted** devices: it formats drives,
> mounts them into internal storage and overrides what the phone reports to apps. **You are responsible**
> for anything that happens to your phone, your SSD, your data or your hardware. No liability is accepted.
> See [§11 Disclaimer](#11-disclaimer).

## What this project adds to the original

The original [pixel-backup-gang](https://github.com/master-hax/pixel-backup-gang) is a clean, purpose-built
toolkit, and it handles the genuinely difficult part: the ext4 mount, SELinux relabelling and the sdcardfs
bind that make Android and its apps see the drive. That foundation is used here.

On top of it, this project adds four conveniences. For context, the original takes the block device as an
argument — its usage line is:

```
Usage: $0 /dev/block/<label> e.g. $0 /dev/block/sdg1
```

**1. It finds the SSD for you.** The block device has to be identified, and the node changes on **every plug**
(`sdg`, `sdh`, `sdh1`, `sdb1`…) because the kernel assigns the next free letter. The original ships
`find_device.sh` and `show_devices.sh` to help look it up. This project adds an automation layer that removes
the lookup entirely — `mount_drive.sh` identifies the drive by its **filesystem label**:

```sh
DEV=$(blkid -t LABEL="$LABEL" | awk '{print $1}' | sed 's/.$//')
```

It also takes care of the details around the mount, automatically: a **stale read-only mount** left by Android
at boot (spots the `(ro` flag, clears it, remounts read-write) and **namespace escalation** (re-execs through
`su -M` so the mount lands in the global namespace where apps can see it — which is what makes it possible to
run the whole thing from a widget). It then fires the **media rescan** so new files appear in Google Photos
without a reboot.

**2. A formatter that lives in the phone.** Two buttons — **Format → ext4** (label `DRIVE`) and
**Format → exFAT** (label `BACKUP`) — format the SSD entirely from the phone, no computer involved. The
exFAT one is the interesting part: Termux ships no `mkfs.exfat`, so the `exfatprogs` package plus the
`libblkid.so` and `libandroid-posix-semaphore.so` libraries it needs are downloaded as `.deb`s, unpacked and
installed into `/data/local/tmp/format-tools/` with the library bootstrap that makes it run. Both formatters
require a typed `YES`, refuse to run while mounted, refuse implausibly small devices, clear the MBR that
`mkfs.exfat` leaves behind (ext4 path), and re-read the partition table when finished.

**3. No terminal.** This project wraps the scripts as Termux:Widget **home-screen buttons** — plug in, tap,
done, with no `adb` session or computer involved. `install.sh` handles the parts that are invisible when you
get them wrong (Termux-user ownership, mode, SELinux context), and every button prints `OK`/`FAILED` and waits
for Enter so the result is readable.

**4. Temp Guard — the reason uploads never stop.** Google Photos pauses or throttles backup once Android
reports a thermal status of MODERATE (2) or higher. A 1 TB first run *will* get the phone warm, so the
upload stalls exactly when it's meant to be running unattended. Temp Guard changes what Android *reports*:

- `cmd thermalservice override-status 0` → apps are told the device is **cool** → Photos keeps uploading
- `cmd thermalservice reset` → real temperature reporting restored

**It does not disable the phone's thermal protection.** It changes only the status value Android reports to
apps — not a hardware setting, and it touches no kernel, thermal HAL or driver. The real thermal layer keeps
measuring true temperature and will still throttle the CPU, reduce charging current when hot, and shut the
device down if it ever became genuinely dangerous. Nothing is disabled, unloaded or bypassed: the upload
stops pausing while the phone keeps protecting itself exactly as before. The override is in-memory (a reboot
clears it) and must be issued through Magisk's `/sbin/su` — Termux's own `su` breaks the binder call to
`thermalservice` ("failed transaction").

⚠️ It stops the *upload* from pausing; it does not cool the phone. Sustained heat still ages batteries —
keep the phone ventilated and give it a break if it's hot to the touch.

---

## Table of contents
1. [Hardware & phone facts](#1-hardware--phone-facts)
2. [The 5 home-screen buttons](#2-the-home-screen-buttons-5)
3. [Files on the phone](#3-files-on-the-phone)
4. [Scripts — full contents](#4-scripts--full-contents)
5. [Modifications to the original scripts](#5-modifications-to-the-original-scripts)
6. [CRITICAL technical gotchas (read this first)](#6-critical-technical-gotchas-read-this-first)
7. [How to rebuild from scratch](#7-how-to-rebuild-from-scratch)
8. [Verified current state](#8-verified-current-state)
9. [Daily workflow](#9-daily-workflow)
10. [Connectivity — direct connection vs powered hub](#10-connectivity--direct-connection-vs-powered-hub)
11. [Disclaimer](#11-disclaimer)

---

## 1. Hardware & phone facts

- **Phone:** Google Pixel XL (`marlin`), **stock Android 10**, rooted with **Magisk 30.7**.
- **Termux:** version `0.119.0-beta.3` (build 1022), installed. Root granted to Termux in Magisk.
- **SSD:** ~1 TB USB-C external SSD.
  - For pixel-backup use: formatted **ext4**, label **`DRIVE`**, whole-disk (no partition table).
    Features: `has_journal extent flex_bg dir_index`, **no** `64bit`, **no** `metadata_csum` (deliberate, for compatibility).
  - For general use on other devices: formatted **exFAT**, label **`BACKUP`**.
- **Connection:** plugging the SSD **directly into the phone's USB-C port** is the recommended setup and the
  one this project is verified on. **A hub is optional, not required.**
  - An **unpowered** hub does **not** work: it tries to run the SSD off the phone's port and there isn't
    enough power, so the drive never enumerates — this is the cause of most "no SSD found" reports.
  - A **powered** hub (with its own PSU) *can* work, but the connect order is mandatory and must be repeated
    on every boot: **SSD directly into the phone first → Mount → verify the capacity in a file browser →
    Unmount → then connect the powered hub → then the SSD into the hub → Mount again.** Full procedure in
    [§10](#10-connectivity--direct-connection-vs-powered-hub).
- The block device name **changes every plug** (`sdg`, `sdh`, `sdh1`, …). Never hardcode it — always find
  by **label** (`blkid -t LABEL=DRIVE`) or by **sysfs path containing `usb`**.

---

## 2. The home-screen buttons (5)

These are **Termux:Widget** widgets. Each widget runs one script from
`/data/data/com.termux/files/home/.shortcuts/`. The scripts are self-contained (no dependencies between them
except the ones noted).

| Button | Script | What it does |
|---|---|---|
| **Mount SSD** | `mount_ssd.sh` | Mounts the ext4 SSD into `/sdcard/the_binding` and rescans media for Google Photos |
| **Unmount SSD** | `unmount_ssd.sh` | Safely unmounts the SSD before unplugging |
| **Format → ext4** | `format_ext4_ssd.sh` | ERASES SSD, formats as **ext4** label `DRIVE` (asks `YES` confirmation) |
| **Format → exFAT** | `format_exfat_ssd.sh` | ERASES SSD, formats as **exFAT** label `BACKUP` (asks `YES` confirmation) |
| **Temp Guard** | `temp_guard.sh` | Toggles the "fake cool" thermal override so Google Photos doesn't pause uploads when the phone is hot |

- **Format safety:** both format buttons open a terminal and ask you to **type `YES` + Enter** to proceed,
  or just **Enter** to cancel. The window stays open until you press Enter so the result is readable.
- Format buttons **refuse to run while the SSD is mounted** ("Tap the Unmount SSD button first").
- The buttons are `dash`-compatible (Termux's `sh` is **dash**, not bash).

---

## 3. Files on the phone

| Path | Purpose |
|---|---|
| `/data/data/com.termux/files/home/.shortcuts/` | The 5 button scripts (owned by Termux user, SELinux `app_data_file`) |
| `/data/local/tmp/pixel-backup-ssd/` | The core scripts (the original mount/unmount scripts + my `mount_drive.sh` helper) |
| `/data/local/tmp/format-tools/` | `mkfs.exfat` + `lib/` (libblkid.so, libandroid-posix-semaphore.so) — needed by the exFAT button |
| `/data/local/tmp/pixel-backup-ssd/mount_drive.sh` | **My** auto-mount helper (the "brain" of the Mount button) |
| `/data/local/tmp/pixel-backup-ssd/mount_ext4.sh` | Original script, **modified** (tolerant namespace guard) |
| `/data/local/tmp/pixel-backup-ssd/unmount.sh` | Original script, **modified** (tolerant namespace guard) |
| `/mnt/my_drive` | Where the SSD is mounted (ext4) |
| `/mnt/my_drive/the_binding` | The folder on the SSD that apps see |
| `/storage/emulated/0/the_binding` | The "internal storage" view of the SSD (this is what apps/Photos see) |

> **Note (Sept 2026):** these scripts used to live in `/data/local/tmp/pixel-backup-gang/`. The folder is now
> `/data/local/tmp/pixel-backup-ssd/`, named after this project rather than the original's. A phone set up
> before the rename still has the old folder — re-run `install.sh` to migrate it, then delete the old one.

The mount is **not persistent** — it is gone after a reboot or unplug. Re-mount with the **Mount SSD** button.

---

## 4. Scripts — full contents

### 4.1 `mount_ssd.sh` (button)
```sh
#!/data/data/com.termux/files/usr/bin/sh
# "Mount SSD" - tap to mount the SSD and rescan so Google Photos sees new files.
echo "=== Mount SSD ==="
if sh /data/local/tmp/pixel-backup-ssd/mount_drive.sh; then
  echo ""
  echo "OK: SSD mounted. New photos should appear in Google Photos."
else
  echo ""
  echo "FAILED - is the SSD plugged into the phone?"
fi
echo "You can close this window now."
```

### 4.2 `unmount_ssd.sh` (button)
```sh
#!/data/data/com.termux/files/usr/bin/sh
# "Unmount SSD" - tap to safely unmount the SSD before unplugging.
# Only relevant when the SSD is mounted in ext4 mode (see the Mount SSD button).
SU="su"; command -v su >/dev/null 2>&1 || SU="/sbin/su"
echo "=== Unmount SSD ==="
if ! grep -q ' /mnt/my_drive ' /proc/mounts; then
  echo "The SSD is not mounted."
  echo "(It's likely exFAT for use on other devices, or not plugged in.)"
  echo "Nothing to unmount - no action needed."
  echo "You can close this window now."
  exit 0
fi
if "$SU" -M -c 'sh /data/local/tmp/pixel-backup-ssd/unmount.sh'; then
  echo ""
  echo "OK: SSD unmounted. Safe to unplug now."
else
  echo ""
  echo "FAILED - see message above."
fi
echo "You can close this window now."
```

### 4.3 `format_ext4_ssd.sh` (button — Format → ext4)
```sh
#!/data/data/com.termux/files/usr/bin/sh
# "Format SSD -> ext4" - ERASES the SSD and formats it as ext4
# (label DRIVE) so the Mount SSD button always finds it.
# Asks for confirmation in the terminal before erasing.

SU="su"; command -v su >/dev/null 2>&1 || SU="/sbin/su"

pause() {
  echo ""
  echo "Press Enter to close this window."
  read DUMMY
}

# --- spinner: show progress while a long command runs ---------------------
# Usage: spin "label" command args...
# Skipped when there is no terminal (e.g. run over adb). The command's own
# output is captured and printed once it finishes, so it doesn't fight the
# spinner for the same line.
spin() {
  _lbl="$1"; shift
  _dir=/data/local/tmp
  [ -w "$_dir" ] || _dir=${TMPDIR:-/tmp}
  if [ ! -t 1 ] || [ ! -w "$_dir" ]; then
    "$@"
    return $?
  fi
  _log="$_dir/.ssd_spin.out"
  _rcl="$_dir/.ssd_spin.rc"
  rm -f "$_rcl" 2>/dev/null
  ( "$@" >"$_log" 2>&1; echo $? >"$_rcl" 2>/dev/null ) &
  _pid=$!
  _n=0
  while [ ! -f "$_rcl" ]; do
    case $((_n % 4)) in
      0) _c='|' ;; 1) _c='/' ;; 2) _c='-' ;; 3) _c='\' ;;
    esac
    printf '\r  %s  %s  (%ss)   ' "$_c" "$_lbl" "$((_n / 5))"
    _n=$((_n + 1))
    sleep 0.2
  done
  wait "$_pid" 2>/dev/null
  printf '\r\033[K'
  cat "$_log" 2>/dev/null
  _rc=$(cat "$_rcl" 2>/dev/null)
  rm -f "$_log" "$_rcl" 2>/dev/null
  return "${_rc:-1}"
}

# --- confirmation (before escalating to root, so it shows in the terminal) ---
if [ "$1" != "CONFIRMED" ]; then
  echo ""
  echo "=============================================="
  echo "!!  WARNING  !!  This will ERASE the SSD."
  echo "Formatting it as ext4 (label DRIVE) for the photo backup."
  echo "=============================================="
  echo ""
  echo "Type YES and press Enter to continue."
  echo "Press Enter alone to CANCEL."
  printf "> "
  read ANS
  case "$ANS" in
    YES|yes|Yes|y) ;;
    *) echo "Cancelled - nothing was changed."
       pause
       exit 0 ;;
  esac
  exec "$SU" -M -c "sh '$0' CONFIRMED"
fi

# --- find the USB SSD (whole disk whose sysfs path contains 'usb') ---
DEV=""
for d in /sys/block/sd*; do
  [ -e "$d" ] || continue
  case "$(readlink "$d" 2>/dev/null)" in *usb*) DEV=$(basename "$d"); break;; esac
done
if [ -z "$DEV" ]; then
  echo ""
  echo "No USB SSD found."
  echo "Is the SSD plugged into the phone?"
  pause
  exit 1
fi
BLOCK="/dev/block/$DEV"
SECTORS=$(cat /sys/block/$DEV/size 2>/dev/null)

# safety: must be a big disk (>= 10 GB) and not mounted
if [ -n "$SECTORS" ] && [ "$SECTORS" -lt 20000000 ]; then
  echo "Refusing: $BLOCK looks too small ($SECTORS sectors). Not the SSD?"
  pause
  exit 1
fi
if mount | grep -q "$BLOCK "; then
  echo ""
  echo "!!  The SSD is currently MOUNTED.  !!"
  echo "Tap the 'Unmount SSD' button first, then try again."
  pause
  exit 1
fi

echo "Erasing and formatting $BLOCK as ext4 (label DRIVE) ..."
# wipe any partition table left by a previous exFAT format, then reformat
dd if=/dev/zero of="$BLOCK" bs=512 count=2048 2>/dev/null
# formatting a 1 TB drive writes the whole inode table, so this can sit there
# for a minute or more - keep a spinner going so it's obvious it isn't stuck
if spin "Writing ext4 filesystem" mkfs.ext4 -F -L DRIVE -O ^metadata_csum,^64bit "$BLOCK"; then
  blockdev --rereadpt "$BLOCK" 2>/dev/null
  echo ""
  echo "DONE: SSD is now ext4 (label DRIVE)."
  echo "Tap 'Mount SSD' to use it for photo backup."
else
  echo ""
  echo "FORMAT FAILED - see message above."
fi
pause
```

### 4.4 `format_exfat_ssd.sh` (button — Format → exFAT)
```sh
#!/data/data/com.termux/files/usr/bin/sh
# "Format SSD -> general (exFAT)" - ERASES the SSD and formats it as exFAT
# (label BACKUP) for use on Mac/Windows/other devices.
# Asks for confirmation in the terminal before erasing.

SU="su"; command -v su >/dev/null 2>&1 || SU="/sbin/su"
TOOLS=/data/local/tmp/format-tools

pause() {
  echo ""
  echo "Press Enter to close this window."
  read DUMMY
}

# --- spinner: show progress while a long command runs ---------------------
# Usage: spin "label" command args...
# Skipped when there is no terminal (e.g. run over adb). The command's own
# output is captured and printed once it finishes, so it doesn't fight the
# spinner for the same line.
spin() {
  _lbl="$1"; shift
  _dir=/data/local/tmp
  [ -w "$_dir" ] || _dir=${TMPDIR:-/tmp}
  if [ ! -t 1 ] || [ ! -w "$_dir" ]; then
    "$@"
    return $?
  fi
  _log="$_dir/.ssd_spin.out"
  _rcl="$_dir/.ssd_spin.rc"
  rm -f "$_rcl" 2>/dev/null
  ( "$@" >"$_log" 2>&1; echo $? >"$_rcl" 2>/dev/null ) &
  _pid=$!
  _n=0
  while [ ! -f "$_rcl" ]; do
    case $((_n % 4)) in
      0) _c='|' ;; 1) _c='/' ;; 2) _c='-' ;; 3) _c='\' ;;
    esac
    printf '\r  %s  %s  (%ss)   ' "$_c" "$_lbl" "$((_n / 5))"
    _n=$((_n + 1))
    sleep 0.2
  done
  wait "$_pid" 2>/dev/null
  printf '\r\033[K'
  cat "$_log" 2>/dev/null
  _rc=$(cat "$_rcl" 2>/dev/null)
  rm -f "$_log" "$_rcl" 2>/dev/null
  return "${_rc:-1}"
}

# --- confirmation (before escalating to root, so it shows in the terminal) ---
if [ "$1" != "CONFIRMED" ]; then
  echo ""
  echo "=============================================="
  echo "!!  WARNING  !!  This will ERASE the SSD."
  echo "Formatting it as exFAT (label BACKUP) for general use."
  echo "=============================================="
  echo ""
  echo "Type YES and press Enter to continue."
  echo "Press Enter alone to CANCEL."
  printf "> "
  read ANS
  case "$ANS" in
    YES|yes|Yes|y) ;;
    *) echo "Cancelled - nothing was changed."
       pause
       exit 0 ;;
  esac
  exec "$SU" -M -c "sh '$0' CONFIRMED"
fi

# --- find the USB SSD (whole disk whose sysfs path contains 'usb') ---
DEV=""
for d in /sys/block/sd*; do
  [ -e "$d" ] || continue
  case "$(readlink "$d" 2>/dev/null)" in *usb*) DEV=$(basename "$d"); break;; esac
done
if [ -z "$DEV" ]; then
  echo ""
  echo "No USB SSD found."
  echo "Is the SSD plugged into the phone?"
  pause
  exit 1
fi
BLOCK="/dev/block/$DEV"
SECTORS=$(cat /sys/block/$DEV/size 2>/dev/null)

# safety: must be a big disk (>= 10 GB) and not mounted
if [ -n "$SECTORS" ] && [ "$SECTORS" -lt 20000000 ]; then
  echo "Refusing: $BLOCK looks too small ($SECTORS sectors). Not the SSD?"
  pause
  exit 1
fi
if mount | grep -q "$BLOCK "; then
  echo ""
  echo "!!  The SSD is currently MOUNTED.  !!"
  echo "Tap the 'Unmount SSD' button first, then try again."
  pause
  exit 1
fi

echo "Erasing and formatting $BLOCK as exFAT (label BACKUP) ..."
# writing the filesystem has a visible pause - keep a spinner going so it's
# obvious the phone is still working
if spin "Writing exFAT filesystem" env LD_LIBRARY_PATH=$TOOLS/lib $TOOLS/mkfs.exfat -F -L BACKUP "$BLOCK"; then
  blockdev --rereadpt "$BLOCK" 2>/dev/null
  echo ""
  echo "DONE: SSD is now exFAT (label BACKUP). Safe to use on Mac/Windows."
  echo "To switch back to the backup drive, tap 'Format -> ext4' then 'Mount SSD'."
else
  echo ""
  echo "FORMAT FAILED - see message above."
fi
pause
```

### 4.5 `mount_drive.sh` (my helper — core of the Mount button)
Lives in `/data/local/tmp/pixel-backup-ssd/mount_drive.sh`.
```sh
#!/system/bin/sh
# mount_drive.sh - auto-mount the ext4 SSD (label: DRIVE) to /the_binding
# and rescan media so new photos/videos show up in Google Photos.
# Works from adb shell AND from app contexts (Termux / Termux:Widget) by
# escalating with `su -M` which runs in the global mount namespace.

LABEL="DRIVE"
BINDING="/storage/emulated/0/the_binding"

# locate su (Termux may not have /sbin on PATH)
SU="su"; command -v su >/dev/null 2>&1 || SU="/sbin/su"

# escalate to root in the global mount namespace if needed
if [ "$(id -u)" != "0" ]; then
  exec "$SU" -M -c "sh '$0' $*"
fi

# (fallback) enter global mount namespace if we aren't in it and can tell
# (guard is tolerant: skip if /proc/1/ns/mnt is unreadable from app contexts)
p1=$(readlink /proc/1/ns/mnt 2>/dev/null)
if [ -n "$p1" ] && [ "$(readlink /proc/self/ns/mnt)" != "$p1" ]; then
  exec nsenter -t 1 -m -- "$0" "$@"
fi

DIR=$(dirname "$0")

if mount | grep -q 'on /mnt/my_drive '; then
  # Android may auto-mount the SSD read-only at boot with a stale device name;
  # detect that and replace it with a proper read-write mount.
  if mount | grep 'on /mnt/my_drive ' | grep -qE '\(ro'; then
    echo "Found a read-only mount (left by Android) - fixing it..."
    sh "$DIR/unmount.sh" >/dev/null 2>&1
  else
    echo "SSD already mounted."
  fi
fi

if ! mount | grep -q 'on /mnt/my_drive '; then
  DEV=$(blkid -t LABEL="$LABEL" | awk '{print $1}' | sed 's/.$//')
  if [ -z "$DEV" ]; then
    echo "SSD with label '$LABEL' not found. Is it plugged into the phone?"
    exit 1
  fi
  echo "Found block device: $DEV"
  echo "Mounting ext4 drive..."
  "$DIR/mount_ext4.sh" "$DEV" || exit 1
fi

# Always rescan the binding so newly synced photos appear in Google Photos.
echo "Rescanning media in $BINDING ..."
am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://$BINDING/ >/dev/null 2>&1
echo "Done. New photos/videos should appear in Google Photos shortly."
```

---

### 4.6 `temp_guard.sh` (button — Temp Guard toggle)
```sh
#!/data/data/com.termux/files/usr/bin/sh
# "Temp Guard" - toggles the fake-cool thermal override for Google Photos.
# ON  -> phone reports "cool" to apps (uploads don't pause for heat).
# OFF -> real temperatures (normal behavior).

# IMPORTANT: use Magisk's /sbin/su. Termux's own 'su' (termux-sudo/tsu) breaks
# binder calls to thermalservice (loses DEVICE_POWER) -> "Failed transaction".
SU="/sbin/su"; [ -e "$SU" ] || SU="su"

# escalate to root (cmd thermalservice needs it)
if [ "$(id -u)" != "0" ]; then
  exec "$SU" -M -c "sh '$0' DONE"
fi

STATE=/data/data/com.termux/files/home/.temp_guard_state

echo "=== Temp Guard ==="
if [ -f "$STATE" ] && grep -q "on" "$STATE" 2>/dev/null; then
  # was ON -> turn it OFF (real temps)
  cmd thermalservice reset
  echo "off" > "$STATE"
  echo ""
  echo "Temp Guard: OFF"
  echo "Phone now reports REAL temperatures to apps."
else
  # was OFF -> turn it ON (fake cool, status 0)
  cmd thermalservice override-status 0
  echo "on" > "$STATE"
  echo ""
  echo "Temp Guard: ON"
  echo "Phone now reports COOL to apps - Google Photos will keep uploading."
fi
# best-effort verification (dumpsys may be blocked from the widget context)
st=$(dumpsys thermalservice 2>/dev/null | grep -o "IsStatusOverride: [a-z]*")
[ -n "$st" ] && echo "  (thermal service now: $st)"
echo ""
echo "Press Enter to close this window."
read DUMMY
```

---

## 5. Modifications to the original scripts

The `mount_ext4.sh` and `unmount.sh` in `/data/local/tmp/pixel-backup-ssd/` come from the
[pixel-backup-gang](https://github.com/master-hax/pixel-backup-gang) project. Two were **modified** and one
was **added**:

### `mount_ext4.sh` (modified)
The original namespace guard:
```sh
if [ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ]; then
  echo "not running in global mount namespace, try elevating first"
  exit 1
fi
```
was replaced with a **tolerant** version (so it works when run from an app context where `/proc/1/ns/mnt`
is not readable — we rely on `su -M` to already be in the global namespace):
```sh
p1=$(readlink /proc/1/ns/mnt 2>/dev/null)
if [ -n "$p1" ] && [ "$(readlink /proc/self/ns/mnt)" != "$p1" ]; then
  echo "not running in global mount namespace, try elevating first"
  exit 1
fi
```
Everything else in `mount_ext4.sh` is unchanged (ext4 mount to `/mnt/my_drive`, sdcardfs bind to
`/mnt/runtime/write/emulated/0/the_binding`, SELinux relabel to `media_rw_data_file`, media-scan broadcast).

### `unmount.sh` (modified)
Same tolerant namespace guard change; the unmounts are unchanged:
```sh
umount -v /mnt/pass_through/0/emulated/0/the_binding
umount -v /mnt/runtime/write/emulated/0/the_binding
umount -v /mnt/my_drive
```
(the `/mnt/pass_through/...` umount prints a harmless "No such file or directory" — it does not exist on this build.)

### `mount_drive.sh` (added — my helper)
See §4.5.

---

### Full modified files (ready to use — paste as-is, no editing needed)

**`/data/local/tmp/pixel-backup-ssd/mount_ext4.sh`:**
```sh
#!/bin/sh -ex

################################################################################
# Description: mounts the specified ext4 block device to /the_binding
# Contributors: Vivek Revankar <vivek@master-hax.com>
# Usage: ./mount_ext4.sh <BLOCK_DEVICE_PATH>
################################################################################

# namespace guard made tolerant: skip if /proc/1/ns/mnt is unreadable
# (we are reached via 'su -M' which already runs in the global namespace)
p1=$(readlink /proc/1/ns/mnt 2>/dev/null)
if [ -n "$p1" ] && [ "$(readlink /proc/self/ns/mnt)" != "$p1" ]; then
  echo "not running in global mount namespace, try elevating first"
  exit 1
fi

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /dev/block/<label> e.g. $0 /dev/block/sdg1" >&2
  exit 1
fi

ext4_blockdev_path=$1

fs_type=$(stat -f -c %T "$ext4_blockdev_path")
if [ "$fs_type" != "tmpfs" ]; then
    echo "detected filesystem type was not 'tmpfs', found $fs_type"
    exit 1
fi

drive_mount_dir='/mnt/my_drive'
internal_binding_dir='/mnt/runtime/write/emulated/0/the_binding'

mkdir -p -v "$drive_mount_dir"
mount \
    -t ext4 \
    -o nosuid,nodev,noexec,noatime \
    "$ext4_blockdev_path" "$drive_mount_dir"

mkdir -p -v "$drive_mount_dir"/the_binding
chmod -R 777 "$drive_mount_dir"/the_binding
chown -R sdcard_rw:sdcard_rw "$drive_mount_dir"

# relabel files on the drive as media_rw_data_file so apps can access it under enforcing selinux
chcon -R u:object_r:media_rw_data_file:s0 "$drive_mount_dir"

mkdir -p -v "$internal_binding_dir"
mount \
    -t sdcardfs \
    -o nosuid,nodev,noexec,noatime,gid=9997 \
    "$drive_mount_dir/the_binding" "$internal_binding_dir"

# TODO: reduce permissions via chmod & sdcardfs mask

am broadcast \
  -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
  -d file:///storage/emulated/0/the_binding/

echo "ext4 drive mounted successfully"
```

**`/data/local/tmp/pixel-backup-ssd/unmount.sh`:**
```sh
#!/bin/sh -x

################################################################################
# Description: unmounts the block device previously mounted by mount_ext4.sh
# Contributors: Vivek Revankar <vivek@master-hax.com>
# Usage: ./unmount.sh
################################################################################

# namespace guard made tolerant: skip if /proc/1/ns/mnt is unreadable
# (we are reached via 'su -M' which already runs in the global namespace)
p1=$(readlink /proc/1/ns/mnt 2>/dev/null)
if [ -n "$p1" ] && [ "$(readlink /proc/self/ns/mnt)" != "$p1" ]; then
  echo "not running in global mount namespace, try elevating first"
  exit 1
fi

umount -v /mnt/pass_through/0/emulated/0/the_binding
umount -v /mnt/runtime/write/emulated/0/the_binding
umount -v /mnt/my_drive
```
(the `/mnt/pass_through/...` umount prints a harmless "No such file or directory" — it does not exist on this build.)

---

## 6. CRITICAL technical gotchas (read this first)

If you ever need to touch these scripts from another machine, these are the rules that make or break it:

1. **Global mount namespace:** For the mount to be visible to apps (Google Photos), it must happen in the
   **global mount namespace**. From an app context (Termux / Termux:Widget) that means escalating with
   **`su -M`** (Magisk's `--mount-master`). `nsenter -t 1 -m` does **not** work from the app context because
   `/proc/1/ns/mnt` isn't accessible there (hence the tolerant guards).

2. **`su` path:** Termux's PATH may not include `/sbin` or `/system/bin`. Always use
   `SU="su"; command -v su >/dev/null 2>&1 || SU="/sbin/su"`.

3. **Double-`su` kills capabilities:** If you test via a chain like `su <termux_uid> -c '... su -M ...'`,
   the second `su` gets **zero capabilities** (CapEff=0) → mount/umount/BLKRRPART fail with EPERM.
   This is a **test-harness artifact only** — the real buttons do a single `su` from the Termux app,
   which has full caps. Don't "fix" anything because of that.

4. **SELinux:** The Termux app (normal app context) **cannot read `/sys/block/*`**. Format scripts must
   escalate to root **before** doing device detection (that's why the format scripts re-exec via `su -M`
   at the very top).

5. **Termux `sh` is dash**, not bash. Scripts must be POSIX/dash-safe (e.g. never put `$(cmd)` inside
   `$(( ))` — dash can't parse that).

6. **Find the device by label, never by name.** Device nodes change every plug (`sdg`/`sdh`/`sdh1`).
   Mount uses `blkid -t LABEL=DRIVE`. Format uses sysfs `readlink /sys/block/sd*` containing `usb`.

7. **Android auto-mounts the SSD read-only at boot** (if plugged in during boot) using a stale device name.
   `mount_drive.sh` detects a `(ro` mount and replaces it with a proper rw mount.

8. **`mkfs.exfat` needs `-F`** to overwrite an existing filesystem (it refuses with
   "device has existing signatures" otherwise). `mkfs.ext4` already has `-F`.

9. **`mkfs.exfat` creates an MBR partition table** (a partition `sdh1` etc.). So:
   - The **ext4 format** first wipes it: `dd if=/dev/zero of=$BLOCK bs=512 count=2048`, then reformats
     the whole disk, then `blockdev --rereadpt`.
   - `blockdev --rereadpt` after each format keeps the kernel in sync (needs CAP_SYS_ADMIN — present in
     real usage via single `su -M`).

10. **Format refuses while mounted.** The format scripts check `mount | grep -q "$BLOCK "` and refuse
    with "Tap the Unmount SSD button first". Unmount first, always.

11. **Unmount before unplugging.** The Unmount button shows a friendly "nothing to unmount" message if the
    SSD isn't mounted (e.g. it's exFAT for use elsewhere).

12. **USB hub = no power = SSD not detected.** The SSD MUST be plugged directly into the phone's USB-C port.
    If the phone reports "no SSD found" for every button, first check the physical connection (no hub).

13. **Wireless adb** (for remote control from a computer):
    - Phone IP on LAN: shown in the phone's Wi-Fi settings (e.g. `192.168.1.x`).
    - Re-enable after a reboot via USB: `adb tcpip 5555`, or from Termux:
      `su -c 'setprop service.adb.tcp.port 5555; stop adbd; start adbd'`.
    - Lost after every reboot (Android 10 has no in-UI wireless-debugging toggle).

14. **ext4 options:** The SSD is formatted with `-O ^metadata_csum,^64bit` (matching the original project's
    docs). Don't change this — the phone's mke2fs 1.44.4 supports it and the setup is proven.

15. **Thermal override (Temp Guard):** Google Photos pauses uploads when the phone reports Thermal Status
    ≥ MODERATE (2). It can be faked without touching the app, at the framework level (root required):
    - `cmd thermalservice override-status 0` → apps see "cool" (status 0/NONE), uploads keep going.
    - `cmd thermalservice reset` → back to real temperatures.
    - The override is **in-memory** → it resets on reboot (tap the button again to re-enable).
    - This only changes what apps *see*; the phone's real hardware protection (thermald/kernel) still works.
    - ⚠️ Must use Magisk's `/sbin/su`. Termux's own `su` (termux-sudo/`tsu`) breaks the binder call to
      thermalservice (`cmd: failure ... Failed transaction`, `DEVICE_POWER` denied). That's why the
      Temp Guard script hardcodes `/sbin/su` instead of `command -v su`.

---

## 7. How to rebuild from scratch

If the phone ever needs to be rebuilt (same machine or another), here are the steps in order:

1. **Install the core scripts** to `/data/local/tmp/pixel-backup-ssd/`:
   - The easy way: run `./install.sh` from this repo on a computer — it deploys all three scripts with the
     right permissions and prints what it did.
   - By hand: copy `mount_drive.sh`, `mount_ext4.sh` and `unmount.sh` out of `scripts/phone/`, `chmod +x`
     them, and place them as root in `/data/local/tmp/pixel-backup-ssd/` (see §4.5 and §5).

2. **Install the exFAT tooling** to `/data/local/tmp/format-tools/` (from the official Termux repo,
   aarch64 `.deb`s — download on a computer, then `adb push` and extract as root on the phone):
   ```
   curl -fsSL -o exfatprogs.deb "https://packages.termux.dev/apt/termux-main/pool/main/e/exfatprogs/exfatprogs_1.4.3_aarch64.deb"
   curl -fsSL -o libblkid.deb  "https://packages.termux.dev/apt/termux-main/pool/main/libb/libblkid/libblkid_2.42.1-4_aarch64.deb"
   curl -fsSL -o libsem.deb     "https://packages.termux.dev/apt/termux-main/pool/main/liba/libandroid-posix-semaphore/libandroid-posix-semaphore_0.1-4_aarch64.deb"
   # Each .deb is an ar archive: extract with bsdtar (macOS tar), then unpack data.tar.xz.
   # (bsdtar can extract the .deb directly: tar -xf <file>.deb, then tar -xf data.tar.xz)
   # Push to the phone as root:
   #   mkfs.exfat  -> /data/local/tmp/format-tools/mkfs.exfat          (chmod 755)
   #   libblkid.so -> /data/local/tmp/format-tools/lib/libblkid.so
   #   libandroid-posix-semaphore.so -> /data/local/tmp/format-tools/lib/
   ```
   Run exFAT format with:
   `LD_LIBRARY_PATH=/data/local/tmp/format-tools/lib /data/local/tmp/format-tools/mkfs.exfat -F -L BACKUP <dev>`

3. **Install Termux:Widget** (com.termux.widget 0.15.0, versionCode 1001) — sideload the APK.

4. **Install the 5 button scripts** (`mount_ssd.sh`, `unmount_ssd.sh`, `format_ext4_ssd.sh`,
   `format_exfat_ssd.sh`, `temp_guard.sh`) into `/data/data/com.termux/files/home/.shortcuts/`, owned by the
   Termux user (`chown` it to the uid that owns the Termux home), `chmod 755`, and set the SELinux context
   to match the Termux home. Copy the context from `~/.termux`:
   `ctx=$(ls -Zd /data/data/com.termux/files/home/.termux | awk '{print $1}')`.

5. **User setup (once):** add 5 Termux:Widget buttons to the home screen, one per script.

6. **Format the SSD** with the Format → ext4 button, then Mount.

---

## 8. Verified current state

- SSD: clean **ext4**, label **`DRIVE`**, whole-disk (no partition), mounted **read-write** at
  `/mnt/my_drive` and visible to apps at `/storage/emulated/0/the_binding` (**916 GB**).
- All 4 buttons work: Mount, Unmount, Format→ext4, Format→exFAT (both formats tested end-to-end).
- Google Photos sees the binding and backs up from it (tested: a photo on the SSD reached the cloud).
- Wireless adb active.

---

## 9. Daily workflow

1. **Plug the SSD directly into the phone.**
2. Tap **Mount SSD** (after reboot/unplug; folder expands to 916 GB = correct).
3. Syncthing (or any app) writes photos into `/storage/emulated/0/the_binding`; run Mount SSD again to rescan,
   and Google Photos backs them up (original quality, free).
4. After backup, delete from the SSD to reuse space (or keep as archive).
5. Tap **Unmount SSD** before unplugging.
6. To switch the SSD to general use: Unmount → **Format → general (exFAT)** → type `YES` → use on Mac/Windows.
7. To switch back to pixel-backup: **Format → pixel-backup (ext4)** → type `YES` → **Mount SSD**.

---

*Note: this document is about the Pixel phone + external SSD setup only. The `warez-0.2.4` folder in the
workspace is a completely separate project (a Godot game) and was NOT touched — no files were added or
modified there.*

---

## 10. Connectivity — direct connection vs powered hub

**A hub is optional.** Direct connection is the simplest and most reliable setup, and the only one this project
was verified on. If you don't specifically need a hub, don't use one.

**Why an unpowered hub fails.** The SSD draws more current than the phone's USB-C port will deliver through a
hub. Without its own supply the hub can't spin the drive up, so it never enumerates — the phone sees nothing
and every button reports "no SSD found". That is a power problem, not a software problem.

**Why the order matters for a powered hub.** Attaching a powered hub with the SSD already in it, and then
expecting the mount helper to find the drive, frequently doesn't work — the device either never appears
cleanly or shows up with a stale identity carried over from a previous boot. Letting the phone see and mount
the SSD **directly first** establishes it properly; only then does the hub path work.

### The sequence (mandatory, every boot)

Steps 1–4 apply **whether or not** you use a hub. The SSD always goes directly into the phone first.

| # | Action | Expected result |
|---|---|---|
| 1 | Phone alone: plug the **SSD directly** into the phone. Nothing else attached — no hub, no other USB accessories. | Phone recognises and powers the drive |
| 2 | Tap **Mount SSD**. | `OK: SSD mounted.` |
| 3 | **Verify**: open any file manager and check the free space of `the_binding`. | Shows the SSD's real capacity (e.g. ~916 GB), **not** 0 B |
| 4 | Tap **Unmount SSD**, wait for the confirmation, then unplug. | Clean release of the direct attachment |
| 5 | Connect the **powered hub** to the phone — power supply connected **and switched on**. | Hub recognised |
| 6 | Plug the **SSD into the hub**. | Drive recognised through the hub |
| 7 | Tap **Mount SSD** again to mount through the hub. | `OK: SSD mounted.` |

**Never skip step 3.** A mount can come up read-only, or carry a stale device name from a previous boot.
Checking the capacity in a file browser is the fast way to confirm the mount is real before you hand it
hundreds of gigabytes.

**If step 7 fails,** the hub or its power supply is at fault. Fall back to a direct connection — that always
works.

---

## 11. Disclaimer

**Use at your own risk. Read this before running anything described in this document.**

This is a hobby project that modifies system-level behaviour on a **rooted** device. It is provided **as-is,
with no warranty of any kind**, express or implied.

By using it you accept that:

- **You are solely responsible for your device, your data and your hardware.** The author(s) and contributors
  accept **no responsibility and no liability** for any damage, data loss, corruption, bricking, overheating,
  fire, injury or financial loss resulting from the use of this software — including any damage to your
  phone, your SSD, your computer, or anything connected to them.
- **The format buttons erase the SSD completely and irreversibly.** There is no undo and no recovery. Be sure
  of the target device and that you don't need its contents.
- **Temp Guard changes what the phone reports to apps.** It does **not** disable kernel or hardware thermal
  protection; the device still throttles and will still shut itself down if it becomes genuinely too hot. But
  it does let the phone keep working — and heating — in conditions where an app would otherwise have paused.
  Sustained heat ages batteries and stresses components. Use it deliberately, keep the phone ventilated, and
  don't leave an overheating device unattended.
- **Rooting voids warranties and weakens the device's security model.**
- **Mounting removable storage into internal storage is inherently risky** — a crash, a bug or a badly-timed
  unplug can leave a filesystem dirty or files half-written.
- **Never rely on a single copy of anything.** Keep another backup of anything you care about.
- **Test before trusting.** Verify the mount, verify the upload, verify the unmount.

If that isn't acceptable to you, don't use this project.

Not affiliated with, endorsed by or supported by Google, Google Photos, Termux, Magisk, or the
`pixel-backup-gang` project. All trademarks belong to their respective owners.
