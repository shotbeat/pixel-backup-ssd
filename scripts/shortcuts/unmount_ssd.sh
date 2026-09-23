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
