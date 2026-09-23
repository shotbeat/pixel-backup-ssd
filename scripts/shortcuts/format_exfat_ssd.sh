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
