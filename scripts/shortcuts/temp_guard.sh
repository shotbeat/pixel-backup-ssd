#!/data/data/com.termux/files/usr/bin/sh
# "Temp Guard" - toggles the fake-cool thermal override for Google Photos.
# ON  -> phone reports "cool" to apps (uploads don't pause for heat).
# OFF -> real temperatures (normal behavior).

# IMPORTANT: use Magisk's /sbin/su. Termux's own 'su' (tsu) breaks binder
# calls to thermalservice (loses DEVICE_POWER), so the override would fail
# with "failed transaction". /sbin/su runs in the permissive magisk context.
SU="/sbin/su"; [ -e "$SU" ] || SU="su"
# state file drives the toggle (don't rely on dumpsys - it can be blocked
# from the widget context, which would make the toggle always go ON)
STATE=/data/data/com.termux/files/home/.temp_guard_state

# escalate to root (cmd thermalservice needs it)
if [ "$(id -u)" != "0" ]; then
  exec "$SU" -M -c "sh '$0' DONE"
fi

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
