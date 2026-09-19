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
if LD_LIBRARY_PATH=$TOOLS/lib $TOOLS/mkfs.exfat -F -L BACKUP "$BLOCK"; then
  blockdev --rereadpt "$BLOCK" 2>/dev/null
  echo ""
  echo "DONE: SSD is now exFAT (label BACKUP). Safe to use on Mac/Windows."
  echo "To use it for pixel-backup again, tap 'Format -> ext4' then 'Mount SSD'."
else
  echo ""
  echo "FORMAT FAILED - see message above."
fi
pause
