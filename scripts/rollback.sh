#!/usr/bin/env bash
# Switch /data/local/bin/server to the other A/B slot and restart the device server.
# Env: DOT2_SERIAL (default G090LF0964340RN6)
set -euo pipefail
SERIAL="${DOT2_SERIAL:-G090LF0964340RN6}"
ADB="${ADB:-adb}"
sh_cmd() { "$ADB" -s "$SERIAL" shell "su -c '$1'"; }

CURRENT="$(sh_cmd 'readlink /data/local/bin/server' | tr -d '\r')"
case "$CURRENT" in
  server_a) TARGET=server_b ;;
  server_b) TARGET=server_a ;;
  *) echo "unexpected symlink target: '$CURRENT'" >&2; exit 1 ;;
esac
echo "switching $CURRENT -> $TARGET"
sh_cmd "ln -sf $TARGET /data/local/bin/server"
PID="$(sh_cmd 'ps' | tr -d '\r' | awk '/data\/local\/bin\/server/ {print $2; exit}')"
[ -n "${PID:-}" ] && sh_cmd "kill -9 $PID" >/dev/null || true
sleep 5
echo "now on $(sh_cmd 'readlink /data/local/bin/server' | tr -d '\r')"
