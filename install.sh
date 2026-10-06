#!/usr/bin/env bash
# eiwifi installer — links the tool into $PREFIX/bin and checks dependencies.
# Safe to re-run.  Usage: bash install.sh [--no-deps]
set -uo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BIN="$PREFIX/bin"
WITH_DEPS=1

for a in "$@"; do
  case "$a" in
    --no-deps) WITH_DEPS=0 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
ok()  { printf '  ✓ %s\n' "$*"; }
warn(){ printf '  ! %s\n' "$*"; }

say "eiwifi installer"
say ""

[ -f "$SRC/eiwifi" ] || die "eiwifi not found next to this script ($SRC)"
[ -d "$PREFIX" ] || die "Termux prefix not found ($PREFIX). Run this inside Termux."

if [ "$WITH_DEPS" = 1 ]; then
  if command -v pkg >/dev/null 2>&1; then
    missing=''
    command -v curl >/dev/null 2>&1 || missing="$missing curl"
    command -v ping >/dev/null 2>&1 || missing="$missing iputils"
    command -v termux-wifi-connectioninfo >/dev/null 2>&1 || missing="$missing termux-api"
    if [ -n "$missing" ]; then
      say "installing:$missing"
      # shellcheck disable=SC2086
      pkg install -y $missing || warn "pkg install failed — run it yourself later"
    else
      ok 'dependencies already present'
    fi
    if ! command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
      warn 'termux-api CLI is present but the Termux:API *app* may be missing.'
      warn 'Install it from F-Droid, then re-run: pkg install termux-api'
    fi
  else
    warn 'pkg not found — skipping dependency install'
  fi
fi

mkdir -p "$BIN" || die "cannot write $BIN"
install -m 0755 "$SRC/eiwifi" "$BIN/eiwifi" || die "cannot install to $BIN"
ln -sf "$BIN/eiwifi" "$BIN/wifi-doctor" 2>/dev/null || true
ok "installed $BIN/eiwifi"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) warn "$BIN is not on PATH — add: export PATH=\"$BIN:\$PATH\"" ;;
esac

say ""
say "Done. Run:"
say "  eiwifi            full report (link, neighbourhood, latency, speed, verdict)"
say "  eiwifi speed 8 20 eight parallel streams for 20s"
say "  eiwifi help"
