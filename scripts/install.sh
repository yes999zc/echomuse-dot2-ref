#!/usr/bin/env bash
# Install a built server binary into the INACTIVE A/B slot and switch to it.
#
#   ./scripts/install.sh artifacts/server [--yes]
#
# The device runs /data/local/bin/start_server.sh, which starts /data/local/bin/server
# (a symlink to server_a or server_b) and restores the previous slot automatically
# after 3 exits shorter than 15 s. This script writes whichever slot is NOT active,
# re-points the symlink and restarts the process; if the new firmware does not come
# up in time it switches back.
#
# Env: DOT2_SERIAL (default G090LF0964340RN6)
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-$ROOT/artifacts/server}"
shift || true
ASSUME_YES=0
for arg in "$@"; do [ "$arg" = "--yes" ] && ASSUME_YES=1; done
SERIAL="${DOT2_SERIAL:-G090LF0964340RN6}"
ADB="${ADB:-adb}"

[ -f "$BIN" ] || { echo "binary not found: $BIN (run scripts/build.sh)" >&2; exit 1; }
command -v "$ADB" >/dev/null || { echo "adb not found" >&2; exit 1; }

sh_cmd() { "$ADB" -s "$SERIAL" shell "su -c '$1'"; }

ACTIVE_TARGET="$(sh_cmd 'readlink /data/local/bin/server' | tr -d '\r')"
case "$ACTIVE_TARGET" in
  server_a) TARGET=server_b; CURRENT=server_a ;;
  server_b) TARGET=server_a; CURRENT=server_b ;;
  *) echo "unexpected /data/local/bin/server target: '$ACTIVE_TARGET'" >&2; exit 1 ;;
esac
echo "active slot: $CURRENT -> writing $TARGET"

if [ "$ASSUME_YES" -ne 1 ]; then
  read -r -p "install $(basename "$BIN") into /data/local/bin/$TARGET and restart the Dot? [y/N] " answer
  [ "$answer" = y ] || [ "$answer" = Y ] || { echo "aborted"; exit 1; }
fi

"$ADB" -s "$SERIAL" push "$BIN" /data/local/tmp/server.new >/dev/null
sh_cmd "cp /data/local/tmp/server.new /data/local/bin/$TARGET && chmod 755 /data/local/bin/$TARGET && rm -f /data/local/tmp/server.new"
echo "written /data/local/bin/$TARGET"

# Restart: start_server.sh (parent shell) brings the server back and re-reads the symlink.
PID="$(sh_cmd 'ps' | tr -s ' ' | awk -F' ' '$NF=="/data/local/bin/server"{print $2; exit}')"
if [ -n "${PID:-}" ]; then
  sh_cmd "kill -9 $PID" >/dev/null || true
else
  echo "warning: running server PID not found; restarting via slot switch anyway"
fi
sh_cmd "ln -sf $TARGET /data/local/bin/server"

echo "waiting for the new firmware..."
for i in $(seq 1 20); do
  sleep 1
  PID="$(sh_cmd 'ps' | tr -s ' ' | awk -F' ' '$NF=="/data/local/bin/server"{print $2; exit}')"
  if [ -n "${PID:-}" ]; then
    sleep 2
    LOG="$("$ADB" -s "$SERIAL" shell "su -c 'cat /tmp/server.log'" 2>/dev/null | tail -c 4000 || true)"
    if printf '%s' "$LOG" | grep -qE "Ready|Registered as|data plane"; then
      echo "ok: new server running (pid $PID, slot $(sh_cmd 'readlink /data/local/bin/server' | tr -d '\r'))"
      exit 0
    fi
  fi
done

echo "new firmware did not report ready; rolling back to $CURRENT" >&2
sh_cmd "ln -sf $CURRENT /data/local/bin/server"
PID="$(sh_cmd 'ps' | tr -s ' ' | awk -F' ' '$NF=="/data/local/bin/server"{print $2; exit}')"
[ -n "${PID:-}" ] && sh_cmd "kill -9 $PID" >/dev/null || true
exit 1
