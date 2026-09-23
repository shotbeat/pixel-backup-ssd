#!/usr/bin/env bash
#
# install.sh — set up pixel-backup-ssd on a rooted Pixel 1 / Pixel XL,
#              driven from a macOS or Linux host over adb.
#
# Usage:
#   ./install.sh                    # auto-detect the connected phone
#   ./install.sh YOUR-SERIAL        # or pass the adb serial explicitly
#   DEVICE=YOUR-SERIAL ./install.sh
#     (find your serial with:  adb devices)
#
# What it does:
#   1. checks adb + root
#   2. pushes the 3 core scripts to  /data/local/tmp/pixel-backup-ssd/
#   3. installs the 5 button scripts to ~/.shortcuts/ inside Termux
#      (correct owner, mode and SELinux context)
#   4. downloads + installs the exFAT tooling (mkfs.exfat + libraries)
#
# It does NOT touch your data. Formatting the SSD is always a manual,
# user-initiated action from the phone's home screen.
#
set -euo pipefail

# ---------------------------------------------------------------- config ----
SSD_DIR="/data/local/tmp/pixel-backup-ssd"
TOOLS_DIR="/data/local/tmp/format-tools"
STAGE_DIR="/data/local/tmp/ssd-stage"
TERMUX_HOME="/data/data/com.termux/files/home"
SHORTCUTS_DIR="$TERMUX_HOME/.shortcuts"
TERMUX_REPO="https://packages.termux.dev/apt/termux-main"
TERMUX_INDEX="$TERMUX_REPO/dists/stable/main/binary-aarch64/Packages.gz"

CORE_SCRIPTS="mount_drive.sh mount_ext4.sh unmount.sh"
BUTTON_SCRIPTS="mount_ssd.sh unmount_ssd.sh format_ext4_ssd.sh format_exfat_ssd.sh temp_guard.sh"

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${1:-${DEVICE:-}}"

# ------------------------------------------------------------- utilities ----
if [ -t 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=''; G=''; Y=''; R=''; N=''
fi
step() { printf '\n%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '%s  ok%s  %s\n'   "$G" "$N" "$*"; }
warn() { printf '%s  !!%s  %s\n'   "$Y" "$N" "$*"; }
die()  { printf '\n%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

adb_s() { adb -s "$DEVICE" "$@"; }
# run a shell command on the phone as root
su_sh() { adb_s shell "su -c '$1'" 2>/dev/null | tr -d '\r'; }

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then usage; fi

# --------------------------------------------------------- 0. prerequisites --
step "Checking prerequisites"

command -v adb >/dev/null 2>&1 \
  || die "adb not found.  macOS: brew install android-platform-tools"
ok "adb found"

[ -d "$REPO_DIR/scripts/phone" ] \
  || die "run this from the repository root (scripts/phone not found)"

if [ -z "$DEVICE" ]; then
  CANDIDATES="$(adb devices | awk 'NR>1 && $2=="device" {print $1}' | grep -v '^emulator-' || true)"
  COUNT="$(printf '%s' "$CANDIDATES" | grep -c . || true)"
  if [ "$COUNT" -eq 0 ]; then
    printf '\n'
    adb devices || true
    die "no phone detected. Enable USB debugging, plug it in, and accept the prompt on screen."
  elif [ "$COUNT" -gt 1 ]; then
    printf '\n%s\n' "$CANDIDATES"
    die "more than one device attached — re-run as: ./install.sh <serial>"
  fi
  DEVICE="$CANDIDATES"
fi
ok "device: $DEVICE"

case "$(adb_s get-state 2>/dev/null || true)" in
  device) ok "adb connection is live" ;;
  *)      die "device $DEVICE is not in 'device' state" ;;
esac

printf '     (if the phone shows a Magisk prompt, tap Allow)\n'
ROOTID="$(su_sh 'id' || true)"
case "$ROOTID" in
  *uid=0*) ok "root available" ;;
  *)       die "could not get root. Is the phone rooted with Magisk and did you grant the prompt?" ;;
esac

# ------------------------------------------------------------ 1. core scripts
step "Installing core scripts -> $SSD_DIR"
# adb push runs as the unprivileged `shell` user, so stage into /data/local/tmp
# (which shell can write to) and let root move the files into place. Pushing
# straight into $SSD_DIR fails on a fresh phone, where root owns that directory.
adb_s shell "rm -rf $STAGE_DIR/phone; mkdir -p $STAGE_DIR/phone" >/dev/null
for f in $CORE_SCRIPTS; do
  adb_s push "$REPO_DIR/scripts/phone/$f" "$STAGE_DIR/phone/$f" >/dev/null
done
su_sh "
  mkdir -p '$SSD_DIR'
  cp -f $STAGE_DIR/phone/*.sh '$SSD_DIR/'
  chmod 755 '$SSD_DIR/'*.sh
" >/dev/null
ok "core scripts installed"

# --------------------------------------------------------- 2. Termux buttons
step "Installing Termux:Widget buttons -> $SHORTCUTS_DIR"

if ! su_sh "[ -d $TERMUX_HOME ] && echo yes" | grep -q yes; then
  die "Termux is not installed. Install it from F-Droid, open it once, then re-run.
       (the Play Store build is abandoned and will not work)"
fi

# Termux's home is mode 700 and owned by the app, so this needs root
T_UID="$(su_sh "stat -c %u $TERMUX_HOME" || true)"
[ -n "$T_UID" ] || die "could not determine the Termux uid"
ok "Termux uid: $T_UID"

# reuse the context of an existing Termux-owned file, so SELinux matches exactly
T_CTX="$(su_sh "ls -Zd $TERMUX_HOME/.termux 2>/dev/null || ls -Zd $TERMUX_HOME" | awk '{print $1}' || true)"
if [ -z "$T_CTX" ]; then
  warn "could not read the SELinux context — skipping chcon"
else
  ok "SELinux context: $T_CTX"
fi

adb_s shell "rm -rf $STAGE_DIR; mkdir -p $STAGE_DIR" >/dev/null
for f in $BUTTON_SCRIPTS; do
  adb_s push "$REPO_DIR/scripts/shortcuts/$f" "$STAGE_DIR/$f" >/dev/null
done

CTX_CMD=""
[ -n "$T_CTX" ] && CTX_CMD="chcon -R $T_CTX '$SHORTCUTS_DIR';"

su_sh "
  mkdir -p '$SHORTCUTS_DIR'
  cp -f $STAGE_DIR/*.sh '$SHORTCUTS_DIR/'
  chown -R $T_UID:$T_UID '$SHORTCUTS_DIR'
  chmod 700 '$SHORTCUTS_DIR'
  chmod 700 '$SHORTCUTS_DIR'/*.sh
  $CTX_CMD
" >/dev/null
ok "5 button scripts installed"

if adb_s shell pm list packages com.termux.widget 2>/dev/null | grep -q termux.widget; then
  ok "Termux:Widget is installed"
else
  warn "Termux:Widget is NOT installed — get it from F-Droid:
       https://f-droid.org/en/packages/com.termux.widget/"
fi

# ------------------------------------------------------- 3. exFAT tooling ----
step "Installing exFAT tooling -> $TOOLS_DIR"

if su_sh "[ -x $TOOLS_DIR/mkfs.exfat ] && echo yes" | grep -q yes; then
  ok "mkfs.exfat already installed, skipping download"
else
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/root" "$TMP/lib"

  deb_url() {  # find the current aarch64 .deb for a package in the Termux repo
    curl -fsSL "$TERMUX_INDEX" 2>/dev/null \
      | gzip -dc 2>/dev/null \
      | awk -v p="$1" '/^Package: /{cur=$2} /^Filename: /{if(cur==p) fn=$2} END{print fn}'
  }

  # dereference symlinks with cat, so each library keeps the exact name the loader asks for
  stage_libs() {
    find "$1" -name 'lib*.so*' 2>/dev/null | while IFS= read -r f; do
      [ -f "$f" ] || continue
      cat "$f" > "$TMP/lib/$(basename "$f")" 2>/dev/null || true
    done
  }

  extract_deb() {
    local deb="$1" out="$2" inner
    mkdir -p "$out"
    if ! tar -xf "$deb" -C "$out" 2>/dev/null; then
      ( cd "$out" && ar x "$deb" ) || return 1
    fi
    inner="$(ls "$out"/data.tar.* 2>/dev/null | head -1)"
    [ -n "$inner" ] || return 1
    tar -xf "$inner" -C "$out" 2>/dev/null
  }

  for pkg in exfatprogs libblkid libandroid-posix-semaphore; do
    url="$(deb_url "$pkg")"
    [ -n "$url" ] || die "could not find package '$pkg' in the Termux repository"
    curl -fsSL -o "$TMP/$pkg.deb" "$TERMUX_REPO/$url" \
      || die "download failed: $TERMUX_REPO/$url"
    extract_deb "$TMP/$pkg.deb" "$TMP/root" || die "could not extract $pkg.deb"
    ok "downloaded $(basename "$url")"
  done

  MKFS="$(find "$TMP/root" -name mkfs.exfat -type f | head -1)"
  [ -n "$MKFS" ] || die "mkfs.exfat was not found inside the downloaded packages"

  stage_libs "$TMP/root"
  [ -f "$TMP/lib/libblkid.so" ] \
    || warn "libblkid.so was not staged — the exFAT button may fail"

  # sanity check: warn about anything the binary loads that we did not stage.
  # Termux links against unversioned sonames (libblkid.so, not libblkid.so.1),
  # and libc/libm/libz/... are provided by Android itself.
  if command -v strings >/dev/null 2>&1; then
    for bin in "$TMP/mkfs.exfat" "$TMP"/lib/*; do
      [ -f "$bin" ] || continue
      strings "$bin" 2>/dev/null | grep -E '^lib.*\.so$' | sort -u |
      while IFS= read -r need; do
        case "$need" in
          libc.so|libm.so|libdl.so|libz.so|liblog.so|libstdc++.so) continue ;;
        esac
        [ -f "$TMP/lib/$need" ] \
          || warn "missing library: $need (required by $(basename "$bin"))"
      done
    done
  fi
  ok "staged: $(ls "$TMP/lib" | tr '\n' ' ')"

  # adb push runs as the unprivileged `shell` user, so stage into /data/local/tmp
  # (shell-writable) and let root copy the files into their final home.
  adb_s shell "mkdir -p $STAGE_DIR/tools/lib" >/dev/null
  cat "$MKFS" > "$TMP/mkfs.exfat"
  adb_s push "$TMP/mkfs.exfat" "$STAGE_DIR/tools/mkfs.exfat" >/dev/null
  for l in "$TMP"/lib/*; do
    [ -f "$l" ] || continue
    adb_s push "$l" "$STAGE_DIR/tools/lib/$(basename "$l")" >/dev/null
  done
  su_sh "
    rm -rf '$TOOLS_DIR'
    mkdir -p '$TOOLS_DIR/lib'
    cp -f $STAGE_DIR/tools/mkfs.exfat '$TOOLS_DIR/mkfs.exfat'
    cp -f $STAGE_DIR/tools/lib/* '$TOOLS_DIR/lib/'
    chmod 755 '$TOOLS_DIR/mkfs.exfat'
    chmod 644 '$TOOLS_DIR/lib/'*
  " >/dev/null
  ok "exFAT tooling installed"
fi

step "Verifying mkfs.exfat"
# NB: mkfs.exfat prints its version and then exits 1, so judge it by the output,
# never by the exit status (this bit the installer once already).
VERSION_RAW="$(su_sh "LD_LIBRARY_PATH=$TOOLS_DIR/lib $TOOLS_DIR/mkfs.exfat -V 2>&1" | head -2 || true)"
if printf '%s' "$VERSION_RAW" | grep -qi 'exfatprogs'; then
  printf '%s\n' "$VERSION_RAW" | awk 'NF' | while IFS= read -r line; do ok "$line"; done
else
  warn "mkfs.exfat did not report a version:"
  printf '       %s\n' "$VERSION_RAW"
  warn "the 'Format -> exFAT' button may not work (ext4 formatting is unaffected)"
fi

# ----------------------------------------------------------- 4. tidy up -----
su_sh "rm -rf $STAGE_DIR" >/dev/null

# ------------------------------------------------------------- done ---------
cat <<EOF

${B}Setup complete.${N}

Final step — add the buttons on the phone:

  1. Long-press an empty spot on the home screen
  2. Widgets  ->  Termux:Widget
  3. Drag out a button, pick a script.  Repeat 5 times.

  ${BUTTON_SCRIPTS}

Then:

  1. Plug the SSD ${B}directly${N} into the phone (a USB hub will not work)
  2. Tap "${B}Mount SSD${N}"                        (format it first if it is new)
  3. Google Photos -> settings -> Backup & sync
     -> Back up device folders -> enable ${B}the_binding${N}
  4. When finished: tap "${B}Unmount SSD${N}", ${B}then${N} unplug.

Full documentation, gotchas and troubleshooting: README.md
EOF
