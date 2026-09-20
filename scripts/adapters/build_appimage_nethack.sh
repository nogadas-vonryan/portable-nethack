#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Build a portable AppImage for NetHack 5.0 using an upstream clone as source.
# Required env:
#   REPO_ROOT   Path to cloned NetHack repository
# Optional env:
#   APP_NAME=NetHack
#   APP_VERSION=5.0.0
#   APPDIR=AppDir
#   OUTPUT_DIR=dist
#   ARCH=x86_64

APP_NAME="${APP_NAME:-NetHack}"
APP_VERSION="${APP_VERSION:-5.0.0}"
APPDIR="${APPDIR:-AppDir}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCH="${ARCH:-x86_64}"

ROOT_DIR="$(resolve_repo_root "nethack")"
cd "$ROOT_DIR"

ABS_APPDIR="$ROOT_DIR/$APPDIR"
ABS_OUTPUT_DIR="$(resolve_output_dir "$ROOT_DIR" "$OUTPUT_DIR")"

# bison/flex (yacc/lex) are required to build NetHack's level compiler output.
need_cmds make gcc pkg-config ldd curl file awk sed grep install gzip bison flex

# Restore config.h so re-runs of this script (or build.sh updates) are idempotent.
# Without this, the sed patch below dirties the git checkout and blocks
# build.sh's fast-forward auto-update on subsequent runs.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git checkout -- include/config.h 2>/dev/null || true
fi

GZIP_PATH="$(command -v gzip)"
echo "==> Using savefile compressor: $GZIP_PATH"

sed -i "s|^#define COMPRESS \"/usr/bin/compress\".*|#define COMPRESS \"$GZIP_PATH\" /* gzip compression */|" include/config.h
sed -i 's|^#define COMPRESS_EXTENSION "\.Z".*|#define COMPRESS_EXTENSION ".gz"      /* gzip extension */|' include/config.h

TERM_LIBS=""
CURSPKG=""
if pkg-config --exists ncursesw; then
  CURSPKG="ncursesw"
  TERM_LIBS="$(pkg-config --libs ncursesw)"
elif pkg-config --exists ncurses; then
  CURSPKG="ncurses"
  TERM_LIBS="$(pkg-config --libs ncurses)"
else
  echo "WARNING: neither ncursesw nor ncurses found via pkg-config; falling back to -lncurses -ltinfo" >&2
  echo "Install libncurses dev files (e.g. sudo apt install libncurses-dev) for curses support." >&2
  TERM_LIBS="-lncurses -ltinfo"
fi
echo "==> Using terminal libs: $TERM_LIBS"

# NOTE: do NOT pass WINLIB= on the make command line. The linux.370/linux.500
# hints files compute WINLIB via 'WINLIB += $(CURSESLIB)'; a command-line
# WINLIB would override that and silently drop curses from the link.
# Pass the tty/curses lib vars instead and let the hints file assemble WINLIB.
MAKE_VARS=(
  WANT_WIN_TTY=1 WANT_WIN_CURSES=1 WANT_DEFAULT=curses
  WINTTYLIB="$TERM_LIBS" WINCURSESLIB="$TERM_LIBS" CURSESLIB="$TERM_LIBS"
)
if [[ -n "$CURSPKG" ]]; then
  MAKE_VARS+=(CURSPKG="$CURSPKG")
fi
mkdir -p "$ABS_OUTPUT_DIR"

# Pick a hints file with curses support. Order matters:
#   linux.500 (NetHack 5.0) -> linux.370 (NetHack 3.7) -> linux (NetHack 3.6,
#   which builds tty+curses unconditionally) -> unix (legacy tty-only fallback).
HINTS_FILE=""
for candidate in sys/unix/hints/linux.500 sys/unix/hints/linux.370 sys/unix/hints/linux sys/unix/hints/unix; do
  if [[ -f "$candidate" ]]; then
    HINTS_FILE="$candidate"
    break
  fi
done
if [[ -z "$HINTS_FILE" ]]; then
  echo "No usable hints file found under sys/unix/hints" >&2
  exit 1
fi
if [[ "$HINTS_FILE" == "sys/unix/hints/unix" ]]; then
  echo "WARNING: falling back to tty-only hints file 'sys/unix/hints/unix'; curses will NOT be built" >&2
fi

echo "==> Running setup.sh $HINTS_FILE to distribute Makefiles"
# A previous run may have distributed Makefiles from a different hints file
# (e.g. legacy tty-only 'unix'); stale Makefiles/objects would then survive
# and the curses objects would never be rebuilt. Clean first if needed.
if [[ -f src/Makefile || -f src/cursmain.o || -f src/wintty.o ]]; then
  echo "==> Cleaning stale objects from previous build configuration"
  make spotless >/dev/null 2>&1 || make clean >/dev/null 2>&1 || true
fi
sh sys/unix/setup.sh "$HINTS_FILE"

# The Lua fetch target is spelled 'fetch-lua' on some branches and
# 'fetch-Lua' in NewInstall.unx; try both so we never silently skip it.
FETCH_LUA_TARGET=""
for candidate in fetch-lua fetch-Lua; do
  if make -n "${MAKE_VARS[@]}" "$candidate" >/dev/null 2>&1; then
    FETCH_LUA_TARGET="$candidate"
    break
  fi
done
if [[ -n "$FETCH_LUA_TARGET" ]]; then
  echo "==> Fetching Lua dependency ($FETCH_LUA_TARGET)"
  make "${MAKE_VARS[@]}" "$FETCH_LUA_TARGET"
else
  echo "==> fetch-lua target not available on this branch; skipping"
fi

echo "==> Building NetHack with curses support (top-level make all)"
make "${MAKE_VARS[@]}" all

# Fail loudly if the curses windowport was not compiled in (silent tty-only
# regression). cursmain.o is only produced when WANT_WIN_CURSES is honoured.
if ! ls src/cursmain.o src/$(uname -m 2>/dev/null)/cursmain.o >/dev/null 2>&1 && \
   ! find src -maxdepth 2 -name 'cursmain.o' -print -quit 2>/dev/null | grep -q .; then
  echo "WARNING: cursmain.o not found; build may be tty-only despite WANT_WIN_CURSES=1" >&2
  echo "Used hints file: $HINTS_FILE" >&2
fi

rm -rf "$ABS_APPDIR"
mkdir -p "$ABS_APPDIR/usr/bin" "$ABS_APPDIR/usr/share/$APP_NAME" "$ABS_APPDIR/usr/lib"

make install \
  HACKDIR="$ABS_APPDIR/usr/share/$APP_NAME" \
  VARDIR="$ABS_APPDIR/usr/share/$APP_NAME" \
  SHELLDIR="$ABS_APPDIR/usr/bin" \
  CHOWN=true CHGRP=true GAMEPERM=0755 \
  "${MAKE_VARS[@]}"

if [[ -x "$ROOT_DIR/src/nethack" ]]; then
  cp "$ROOT_DIR/src/nethack" "$ABS_APPDIR/usr/bin/nethack-bin"
elif [[ -x "$ABS_APPDIR/usr/share/$APP_NAME/nethack" ]]; then
  cp "$ABS_APPDIR/usr/share/$APP_NAME/nethack" "$ABS_APPDIR/usr/bin/nethack-bin"
else
  echo "Could not find built nethack binary" >&2
  exit 1
fi

write_seed_manifest "$ABS_APPDIR/usr/share/$APP_NAME"

cat > "$ABS_APPDIR/AppRun" <<EOF
#!/usr/bin/env bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
export LD_LIBRARY_PATH="\$HERE/usr/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
RUNTIME_BASE="\${XDG_DATA_HOME:-\$HOME/.local/share}"
RUNTIME_DIR="\$RUNTIME_BASE/$APP_NAME"
SEED_DIR="\$HERE/usr/share/$APP_NAME"
SEED_VERSION="$APP_VERSION"

mkdir -p "\$RUNTIME_DIR"

if [[ ! -f "\$RUNTIME_DIR/perm" ]]; then
  cp -an "\$SEED_DIR/." "\$RUNTIME_DIR/"
elif [[ "\$(cat "\$RUNTIME_DIR/.app-version" 2>/dev/null)" != "\$SEED_VERSION" ]]; then
  # AppImage upgraded: refresh packaged seed files, preserving user state
  # (saves, records, logs, customized sysconf).
  if [[ -f "\$RUNTIME_DIR/.seed-manifest" ]]; then
    while IFS= read -r -d '' seed_file; do
      case "\$seed_file" in
        ./sysconf|./perm|./record|./logfile|./xlogfile|./livelog|./save/*|./dumplog/*)
          continue
          ;;
      esac
      if [[ -e "\$SEED_DIR/\$seed_file" || -L "\$SEED_DIR/\$seed_file" ]]; then
        mkdir -p "\$RUNTIME_DIR/\$(dirname "\$seed_file")"
        cp -a "\$SEED_DIR/\$seed_file" "\$RUNTIME_DIR/\$seed_file"
      fi
    done < "\$RUNTIME_DIR/.seed-manifest"
  fi
  cp -an "\$SEED_DIR/." "\$RUNTIME_DIR/"
fi
cp -a "\$SEED_DIR/.seed-manifest" "\$RUNTIME_DIR/.seed-manifest"
echo "\$SEED_VERSION" > "\$RUNTIME_DIR/.app-version"

if [[ ! -f "\$RUNTIME_DIR/sysconf" && -f "\$SEED_DIR/sysconf" ]]; then
  cp -a "\$SEED_DIR/sysconf" "\$RUNTIME_DIR/sysconf"
fi
if [[ ! -f "\$RUNTIME_DIR/sysconf" ]]; then
  cat > "\$RUNTIME_DIR/sysconf" <<'SYSCONF_EOF'
WIZARDS=*
EXPLORERS=*
MAXPLAYERS=10
SYSCONF_EOF
fi

touch "\$RUNTIME_DIR/perm" "\$RUNTIME_DIR/record" "\$RUNTIME_DIR/logfile" "\$RUNTIME_DIR/xlogfile" "\$RUNTIME_DIR/livelog"
mkdir -p "\$RUNTIME_DIR/save" "\$RUNTIME_DIR/dumplog"
chmod u+rw "\$RUNTIME_DIR/perm" "\$RUNTIME_DIR/record" "\$RUNTIME_DIR/logfile" "\$RUNTIME_DIR/xlogfile" "\$RUNTIME_DIR/livelog" || true

cd "\$RUNTIME_DIR"
export HACKDIR="\$RUNTIME_DIR"
exec "\$HERE/usr/bin/nethack-bin" -d "\$RUNTIME_DIR" "\$@"
EOF
chmod +x "$ABS_APPDIR/AppRun"

cat > "$ABS_APPDIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=NetHack
GenericName=Roguelike Game
Comment=NetHack vanilla
Exec=nethack-bin
Icon=$APP_NAME
Terminal=true
Categories=Game;RolePlaying;
EOF

cat > "$ABS_APPDIR/$APP_NAME.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" fill="#101820"/>
  <rect x="16" y="16" width="224" height="224" fill="#1f2937" stroke="#f59e0b" stroke-width="8"/>
  <text x="128" y="142" text-anchor="middle" fill="#f59e0b" font-family="monospace" font-size="84" font-weight="700">NH</text>
</svg>
EOF

copy_needed_libs "$ABS_APPDIR" "$ABS_APPDIR/usr/bin/nethack-bin"
patch_rpath_if_available "$ABS_APPDIR/usr/bin/nethack-bin"

download_appimage_tools "$ARCH"
build_appimage "$ABS_APPDIR" "$ABS_OUTPUT_DIR" "$APP_NAME" "$APP_VERSION" "$ARCH" "$ABS_APPDIR/$APP_NAME.desktop" "$ABS_APPDIR/$APP_NAME.svg"
