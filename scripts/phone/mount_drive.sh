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
