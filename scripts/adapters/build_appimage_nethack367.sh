#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Wrapper adapter for NetHack 3.6.7.
# Reuses the standard NetHack adapter with a different default version.
: "${APP_VERSION:=3.6.7}"

exec bash "$SCRIPT_DIR/build_appimage_nethack.sh"
