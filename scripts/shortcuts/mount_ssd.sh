#!/data/data/com.termux/files/usr/bin/sh
# "Mount SSD" - tap to mount the SSD and rescan so Google Photos sees new files.
echo "=== Mount SSD ==="
if sh /data/local/tmp/pixel-backup-gang/mount_drive.sh; then
  echo ""
  echo "OK: SSD mounted. New photos should appear in Google Photos."
else
  echo ""
  echo "FAILED - is the SSD plugged into the phone?"
fi
echo "You can close this window now."
