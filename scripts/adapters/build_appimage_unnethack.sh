#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Build a portable AppImage for UnNetHack using an upstream clone as source.
# Required env:
#   REPO_ROOT   Path to cloned UnNetHack repository
# Optional env:
#   APP_NAME=UnNetHack
#   APP_VERSION=7.0.0
#   APPDIR=AppDir
#   OUTPUT_DIR=dist
#   ARCH=x86_64

APP_NAME="${APP_NAME:-UnNetHack}"
APP_VERSION="${APP_VERSION:-7.0.0}"
APPDIR="${APPDIR:-AppDir}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCH="${ARCH:-x86_64}"

ROOT_DIR="$(resolve_repo_root "unnethack")"
cd "$ROOT_DIR"

ABS_APPDIR="$ROOT_DIR/$APPDIR"
ABS_OUTPUT_DIR="$(resolve_output_dir "$ROOT_DIR" "$OUTPUT_DIR")"

need_cmds make gcc pkg-config ldd curl file awk sed grep install gzip tar

TERM_LIBS=""
if pkg-config --exists ncursesw; then
  TERM_LIBS="$(pkg-config --libs ncursesw)"
elif pkg-config --exists ncurses; then
  TERM_LIBS="$(pkg-config --libs ncurses)"
else
  TERM_LIBS="-lncurses -ltinfo"
fi
echo "==> Using terminal libs: $TERM_LIBS"

# Avoid host-dependent compressor path failures at runtime by disabling
# external save-file compression inside the AppImage build.
echo "==> Disabling external savefile compression for portability"
sed -i 's|^#define COMPRESS .*|/* #define COMPRESS */|' include/config.h
sed -i 's|^#define COMPRESS_EXTENSION .*|/* #define COMPRESS_EXTENSION */|' include/config.h

# This branch has several references guarded behind RECORD_ACHIEVE while
# still used in always-built code paths. Enable XLOGFILE so RECORD_ACHIEVE
# is consistently defined.
if ! grep -Eq '^[[:space:]]*#define[[:space:]]+XLOGFILE' include/config.h; then
  sed -i 's|^[[:space:]]*/\*[[:space:]]*#define[[:space:]]\+XLOGFILE[[:space:]]\+"xlogfile"[[:space:]]*\*/.*|#define XLOGFILE "xlogfile"|' include/config.h
fi

if ! grep -Eq '^[[:space:]]*#define[[:space:]]+XLOGFILE' include/config.h; then
  # Defensive fallback if XLOGFILE is still unavailable.
  tmp_rm_h="$(mktemp)"
  awk '
    BEGIN { replaced = 0 }
    /^#define[[:space:]]+Sokoban[[:space:]]/ {
      print "#define Sokoban (In_sokoban(&u.uz))"
      replaced = 1
      next
    }
    { print }
    END {
      if (!replaced) {
        print "#define Sokoban (In_sokoban(&u.uz))"
      }
    }
  ' include/rm.h > "$tmp_rm_h"
  mv "$tmp_rm_h" include/rm.h
else
  # Ensure any previous fallback rewrite is restored to achievement-aware form.
  tmp_rm_h="$(mktemp)"
  awk '
    BEGIN { replaced = 0 }
    /^#define[[:space:]]+Sokoban[[:space:]]/ {
      print "#define Sokoban (In_sokoban(&u.uz) && !achieve.solved_sokoban)"
      replaced = 1
      next
    }
    { print }
    END {
      if (!replaced) {
        print "#define Sokoban (In_sokoban(&u.uz) && !achieve.solved_sokoban)"
      }
    }
  ' include/rm.h > "$tmp_rm_h"
  mv "$tmp_rm_h" include/rm.h
fi

mkdir -p "$ABS_OUTPUT_DIR"

LUA_CFLAGS=""
LUA_LIBS=""
LUA_BIN=""
if pkg-config --exists lua5.4; then
  LUA_CFLAGS="$(pkg-config --cflags lua5.4)"
  LUA_LIBS="$(pkg-config --libs lua5.4)"
elif pkg-config --exists lua-5.4; then
  LUA_CFLAGS="$(pkg-config --cflags lua-5.4)"
  LUA_LIBS="$(pkg-config --libs lua-5.4)"
elif [[ -f /usr/include/lua5.4/lua.h ]]; then
  LUA_CFLAGS="-I/usr/include/lua5.4"
  LUA_LIBS="-llua5.4"
fi

for candidate in lua5.4 lua54 lua; do
  if command -v "$candidate" >/dev/null 2>&1; then
    LUA_BIN="$(command -v "$candidate")"
    break
  fi
done

if [[ -z "$LUA_BIN" ]]; then
  LUA_BOOTSTRAP_VERSION="5.4.7"
  LUA_BOOTSTRAP_ROOT="$ROOT_DIR/.build"
  LUA_BOOTSTRAP_SRC="$LUA_BOOTSTRAP_ROOT/lua-$LUA_BOOTSTRAP_VERSION"
  LUA_BOOTSTRAP_TGZ="$LUA_BOOTSTRAP_ROOT/lua-$LUA_BOOTSTRAP_VERSION.tar.gz"

  mkdir -p "$LUA_BOOTSTRAP_ROOT"
  if [[ ! -x "$LUA_BOOTSTRAP_SRC/src/lua" ]]; then
    echo "==> Bootstrapping local Lua interpreter $LUA_BOOTSTRAP_VERSION"
    curl -fsSL "https://www.lua.org/ftp/lua-$LUA_BOOTSTRAP_VERSION.tar.gz" -o "$LUA_BOOTSTRAP_TGZ"
    tar -xzf "$LUA_BOOTSTRAP_TGZ" -C "$LUA_BOOTSTRAP_ROOT"
    make -C "$LUA_BOOTSTRAP_SRC/src" linux
  fi

  LUA_BIN="$LUA_BOOTSTRAP_SRC/src/lua"
  LUA_CFLAGS="-I$LUA_BOOTSTRAP_SRC/src"
  LUA_LIBS="$LUA_BOOTSTRAP_SRC/src/liblua.a -lm -ldl"
fi

echo "==> Using Lua interpreter: $LUA_BIN"

if [[ -n "$LUA_CFLAGS" ]]; then
  echo "==> Using Lua CFLAGS: $LUA_CFLAGS"
fi
if [[ -n "$LUA_LIBS" ]]; then
  echo "==> Using Lua LIBS: $LUA_LIBS"
fi

ensure_legacy_header() {
  local legacy_name="$1"
  local header_path="include/$legacy_name"
  local legacy_base="${legacy_name%.*}"
  local guard_name
  guard_name="PORTABLE_NETHACK_LEGACY_$(printf '%s' "$legacy_base" | tr '[:lower:]' '[:upper:]')_H"

  if [[ -f "$header_path" ]]; then
    return
  fi

  cat > "$header_path" <<EOF
#ifndef $guard_name
#define $guard_name
#include "mextra.h"
#endif
EOF
}

# Some UnNetHack branches merged these headers into mextra.h but still list
# the legacy names as Makefile prerequisites.
ensure_legacy_header "eshk.h"
ensure_legacy_header "epri.h"
ensure_legacy_header "emin.h"
ensure_legacy_header "vault.h"

ensure_trampoli_header() {
  local header_path="include/trampoli.h"

  if [[ -f "$header_path" ]]; then
    return
  fi

  cat > "$header_path" <<'EOF'
#ifndef PORTABLE_NETHACK_LEGACY_TRAMPOLI_H
#define PORTABLE_NETHACK_LEGACY_TRAMPOLI_H
/* Compatibility shim for branches that no longer ship trampoli.h. */
#endif
EOF
}

ensure_trampoli_header

OWNER_USER="$(id -un)"
OWNER_GROUP="$(id -gn)"

CONFIGURE_ENV=()
CONFIGURE_ENV+=("LUA=$LUA_BIN")
if [[ -n "$LUA_CFLAGS" ]]; then
  CONFIGURE_ENV+=("LUA_INCLUDE=$LUA_CFLAGS")
fi
if [[ -n "$LUA_LIBS" ]]; then
  CONFIGURE_ENV+=("LUA_LIB=$LUA_LIBS")
fi

echo "==> Configuring UnNetHack (autoconf)"
env "${CONFIGURE_ENV[@]}" ./configure \
  --prefix=/usr \
  --with-owner="$OWNER_USER" \
  --with-group="$OWNER_GROUP" \
  --enable-tty-graphics \
  --disable-curses-graphics \
  --disable-x11-graphics \
  --disable-file-areas

echo "==> Building UnNetHack (autoconf make all)"
make all

rm -rf "$ABS_APPDIR"
mkdir -p "$ABS_APPDIR/usr/bin" "$ABS_APPDIR/usr/lib"

echo "==> Installing into AppDir"
make install DESTDIR="$ABS_APPDIR" CHOWN=true CHGRP=true CHMOD=true

BIN_SOURCE=""

is_elf_binary() {
  local path="$1"
  [[ -x "$path" ]] || return 1
  file -Lb "$path" | grep -qi '^ELF'
}

# Prefer the actual game binary over installed wrapper scripts.
for candidate in \
  "$ABS_APPDIR/usr/share/unnethack/unnethack" \
  "$ABS_APPDIR/usr/lib/unnethack/unnethack" \
  "$ABS_APPDIR/usr/games/lib/unnethackdir/unnethack" \
  "$ROOT_DIR/src/unnethack" \
  "$ABS_APPDIR/usr/share/unnethack/nethack" \
  "$ABS_APPDIR/usr/lib/unnethack/nethack" \
  "$ROOT_DIR/src/nethack" \
  "$ABS_APPDIR/usr/games/unnethack" \
  "$ABS_APPDIR/usr/bin/unnethack"
do
  if is_elf_binary "$candidate"; then
    BIN_SOURCE="$candidate"
    break
  fi
done

if [[ -z "$BIN_SOURCE" ]]; then
  # Fallback if `file` is unavailable or upstream layout is unusual.
  for candidate in \
    "$ABS_APPDIR/usr/share/unnethack/unnethack" \
    "$ABS_APPDIR/usr/lib/unnethack/unnethack" \
    "$ABS_APPDIR/usr/games/lib/unnethackdir/unnethack" \
    "$ROOT_DIR/src/unnethack" \
    "$ABS_APPDIR/usr/share/unnethack/nethack" \
    "$ABS_APPDIR/usr/lib/unnethack/nethack" \
    "$ROOT_DIR/src/nethack" \
    "$ABS_APPDIR/usr/games/unnethack" \
    "$ABS_APPDIR/usr/bin/unnethack"
  do
    if [[ -x "$candidate" ]]; then
      BIN_SOURCE="$candidate"
      break
    fi
  done
fi

if [[ -z "$BIN_SOURCE" ]]; then
  echo "Could not find built UnNetHack binary" >&2
  exit 1
fi

INSTALL_SEED_DIR=""
for candidate in \
  "$ABS_APPDIR/usr/share/unnethack" \
  "$ABS_APPDIR/usr/lib/unnethack" \
  "$ABS_APPDIR/usr/games/lib/unnethackdir"
do
  if [[ -d "$candidate" && ( -f "$candidate/options" || -f "$candidate/nhdat" || -f "$candidate/unnethackrc.default" ) ]]; then
    INSTALL_SEED_DIR="$candidate"
    break
  fi
done

if [[ -z "$INSTALL_SEED_DIR" ]]; then
  echo "Could not find installed UnNetHack data directory" >&2
  exit 1
fi

SEED_DIR_REL="${INSTALL_SEED_DIR#$ABS_APPDIR}"
if [[ "$SEED_DIR_REL" == "$INSTALL_SEED_DIR" ]]; then
  SEED_DIR_REL="/usr/share/unnethack"
fi

cp "$BIN_SOURCE" "$ABS_APPDIR/usr/bin/unnethack-bin"

if [[ ! -x "$ABS_APPDIR/usr/bin/unnethack-bin" ]]; then
  chmod +x "$ABS_APPDIR/usr/bin/unnethack-bin"
fi

cat > "$ABS_APPDIR/AppRun" <<EOF
#!/usr/bin/env bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
export LD_LIBRARY_PATH="\$HERE/usr/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
RUNTIME_BASE="\${XDG_DATA_HOME:-\$HOME/.local/share}"
RUNTIME_DIR="\$RUNTIME_BASE/UnNetHack-AppImage"
SEED_DIR="\$HERE$SEED_DIR_REL"

mkdir -p "\$RUNTIME_DIR"

if [[ ! -f "\$RUNTIME_DIR/perm" ]]; then
  cp -an "\$SEED_DIR/." "\$RUNTIME_DIR/"
fi

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
GAME_BIN="\$RUNTIME_DIR/unnethack"
if [[ ! -x "\$GAME_BIN" ]]; then
  GAME_BIN="\$HERE/usr/bin/unnethack-bin"
fi

case "\${1:-}" in
  -s*)
    exec "\$GAME_BIN" -d "\$RUNTIME_DIR" "\$@"
    ;;
  *)
    exec "\$GAME_BIN" -d "\$RUNTIME_DIR" "\$@" 4
    ;;
esac
EOF
chmod +x "$ABS_APPDIR/AppRun"

cat > "$ABS_APPDIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=UnNetHack
GenericName=Roguelike Game
Comment=UnNetHack NetHack variant
Exec=unnethack-bin
Icon=$APP_NAME
Terminal=true
Categories=Game;RolePlaying;
EOF

cat > "$ABS_APPDIR/$APP_NAME.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" fill="#0f172a"/>
  <rect x="16" y="16" width="224" height="224" fill="#1e293b" stroke="#38bdf8" stroke-width="8"/>
  <text x="128" y="142" text-anchor="middle" fill="#bae6fd" font-family="monospace" font-size="52" font-weight="700">UNH</text>
</svg>
EOF

copy_needed_libs "$ABS_APPDIR" "$ABS_APPDIR/usr/bin/unnethack-bin"
patch_rpath_if_available "$ABS_APPDIR/usr/bin/unnethack-bin"

download_appimage_tools "$ARCH"
build_appimage "$ABS_APPDIR" "$ABS_OUTPUT_DIR" "$APP_NAME" "$APP_VERSION" "$ARCH" "$ABS_APPDIR/$APP_NAME.desktop" "$ABS_APPDIR/$APP_NAME.svg"
