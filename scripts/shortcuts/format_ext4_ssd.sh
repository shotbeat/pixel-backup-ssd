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
if mkfs.ext4 -F -L DRIVE -O ^metadata_csum,^64bit "$BLOCK"; then
  blockdev --rereadpt "$BLOCK" 2>/dev/null
  echo ""
  echo "DONE: SSD is now ext4 (label DRIVE)."
    echo "Tap 'Mount SSD' to use it for photo backup."
else
  echo ""
  echo "FORMAT FAILED - see message above."
fi
pause
