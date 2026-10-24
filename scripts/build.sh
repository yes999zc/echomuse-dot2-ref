#!/usr/bin/env bash
# Clone EchoMuse at the pinned tag, apply the patch, cross-compile the device server.
#
#   ./scripts/build.sh [workdir]
#
# Env:
#   EM_TAG   upstream tag to build (default v2.19.0-ea.1)
#   EM_REPO  upstream repository (default https://github.com/wilbowes/EchoMuse.git)
#   DOCKER   docker binary (default: docker on PATH, else OrbStack)
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:-/tmp/echomuse-ref-build}"
TAG="${EM_TAG:-v2.19.0-ea.1}"
REPO="${EM_REPO:-https://github.com/wilbowes/EchoMuse.git}"
PATCH="$(ls "$ROOT"/patches/0001-ref-uplink-*.patch | head -1)"
DOCKER="${DOCKER:-docker}"

export PATH="/opt/homebrew/bin:$HOME/.orbstack/bin:$PATH"
if [ -z "${DOCKER_HOST:-}" ] && [ -S "$HOME/.orbstack/run/docker.sock" ]; then
  export DOCKER_HOST="unix://$HOME/.orbstack/run/docker.sock"
fi

[ -n "$PATCH" ] || { echo "no patch under $ROOT/patches" >&2; exit 1; }
command -v "$DOCKER" >/dev/null || { echo "docker not found" >&2; exit 1; }

echo "== workdir $WORK (tag $TAG)"
rm -rf "$WORK"
git clone --depth 1 --branch "$TAG" "$REPO" "$WORK"

# The device build replaces GoTinyAlsa with the sibling checkout; it is a git
# submodule and an uninitialised one fails with "reading /GoTinyAlsa/go.mod".
git -C "$WORK" submodule update --init --depth 1 GoTinyAlsa

echo "== applying $(basename "$PATCH")"
git -C "$WORK" apply --index "$PATCH"
git -C "$WORK" diff --stat --cached

echo "== compiler image (first run pulls NDK + Go 1.24)"
if ! "$DOCKER" image inspect echomuse-compiler >/dev/null 2>&1; then
  "$DOCKER" build -t echomuse-compiler "$WORK/device/compiler"
fi

echo "== cross-compiling"
( cd "$WORK/device" && ./compile.sh )

BIN="$WORK/device/build/server"
[ -f "$BIN" ] || { echo "build/server missing" >&2; exit 1; }
mkdir -p "$ROOT/artifacts"
cp "$BIN" "$ROOT/artifacts/server"
chmod 755 "$ROOT/artifacts/server"

echo "== artifact"
ls -l "$ROOT/artifacts/server"
shasum -a 256 "$ROOT/artifacts/server" | tee "$ROOT/artifacts/server.sha256"
file "$ROOT/artifacts/server"
echo
echo "install (deliberate; reboots the Dot's audio pipeline):"
echo "  ./scripts/install.sh artifacts/server --yes"
