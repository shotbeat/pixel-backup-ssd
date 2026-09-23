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
