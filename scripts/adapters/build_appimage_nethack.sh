#!/usr/bin/env bash
set -euo pipefail

# Build a portable AppImage for NetHack 3.7 using an upstream clone as source.
# Required env:
#   REPO_ROOT   Path to cloned NetHack repository
# Optional env:
#   APP_NAME=NetHack
#   APP_VERSION=3.7.0
#   APPDIR=AppDir
#   OUTPUT_DIR=dist
#   ARCH=x86_64
#   SKIP_GIT_UPDATE=1

APP_NAME="${APP_NAME:-NetHack}"
APP_VERSION="${APP_VERSION:-3.7.0}"
APPDIR="${APPDIR:-AppDir}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCH="${ARCH:-x86_64}"

if [[ -n "${REPO_ROOT:-}" ]]; then
  ROOT_DIR="$REPO_ROOT"
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.work/nethack"
fi

cd "$ROOT_DIR"

ABS_APPDIR="$ROOT_DIR/$APPDIR"
ABS_OUTPUT_DIR="$OUTPUT_DIR"

case "$ABS_OUTPUT_DIR" in
  /*) ;;
  *) ABS_OUTPUT_DIR="$ROOT_DIR/$ABS_OUTPUT_DIR" ;;
esac

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd make
need_cmd gcc
need_cmd pkg-config
need_cmd ldd
need_cmd curl
need_cmd file
need_cmd awk
need_cmd sed
need_cmd grep
need_cmd install
need_cmd gzip

GZIP_PATH="$(command -v gzip)"
echo "==> Using savefile compressor: $GZIP_PATH"

# NetHack's default UNIX config uses /usr/bin/compress, which is often missing.
sed -i "s|^#define COMPRESS \"/usr/bin/compress\".*|#define COMPRESS \"$GZIP_PATH\" /* gzip compression */|" include/config.h
sed -i 's|^#define COMPRESS_EXTENSION "\.Z".*|#define COMPRESS_EXTENSION ".gz"      /* gzip extension */|' include/config.h

TERM_LIBS=""
if pkg-config --exists ncursesw; then
  TERM_LIBS="$(pkg-config --libs ncursesw)"
elif pkg-config --exists ncurses; then
  TERM_LIBS="$(pkg-config --libs ncurses)"
else
  TERM_LIBS="-lncurses -ltinfo"
fi
echo "==> Using terminal libs: $TERM_LIBS"

MAKE_VARS=(WINTTYLIB="$TERM_LIBS" WINLIB="$TERM_LIBS")

mkdir -p "$ABS_OUTPUT_DIR"

echo "==> Running setup.sh sys/unix/hints/unix to distribute Makefiles"
sh sys/unix/setup.sh sys/unix/hints/unix

echo "==> Fetching Lua dependency"
make "${MAKE_VARS[@]}" fetch-lua

echo "==> Building NetHack (top-level make all)"
make "${MAKE_VARS[@]}" all

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

cat > "$ABS_APPDIR/AppRun" <<EOF
#!/usr/bin/env bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
export LD_LIBRARY_PATH="\$HERE/usr/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
RUNTIME_BASE="\${XDG_DATA_HOME:-\$HOME/.local/share}"
RUNTIME_DIR="\$RUNTIME_BASE/$APP_NAME"
SEED_DIR="\$HERE/usr/share/$APP_NAME"

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

copy_needed_libs() {
  local bin="$1"
  ldd "$bin" | awk '/=> \/|^\// { for (i=1; i<=NF; ++i) if ($i ~ /^\//) print $i }' | while IFS= read -r lib; do
    [[ -z "$lib" ]] && continue
    local base
    base="$(basename "$lib")"
    case "$base" in
      linux-vdso.so.*|ld-linux*.so*|libc.so.*|libm.so.*|libpthread.so.*|librt.so.*|libdl.so.*|libutil.so.*|libresolv.so.*)
        continue
        ;;
    esac
    if [[ ! -e "$ABS_APPDIR/usr/lib/$base" ]]; then
      cp -a "$lib" "$ABS_APPDIR/usr/lib/"
    fi
  done
}

copy_needed_libs "$ABS_APPDIR/usr/bin/nethack-bin"

if command -v patchelf >/dev/null 2>&1; then
  patchelf --set-rpath '$ORIGIN/../lib' "$ABS_APPDIR/usr/bin/nethack-bin" || true
else
  echo "patchelf not found; skipping RPATH patch (LD_LIBRARY_PATH in AppRun still handles runtime)"
fi

TMP_BIN_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_BIN_DIR"
}
trap cleanup EXIT

case "$ARCH" in
  x86_64)
    LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${ARCH}.AppImage"
    APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage"
    ;;
  aarch64)
    LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${ARCH}.AppImage"
    APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-aarch64.AppImage"
    ;;
  *)
    echo "Unsupported ARCH: $ARCH" >&2
    exit 1
    ;;
esac

echo "==> Downloading linuxdeploy + appimagetool"
curl -fsSL "$LINUXDEPLOY_URL" -o "$TMP_BIN_DIR/linuxdeploy"
curl -fsSL "$APPIMAGETOOL_URL" -o "$TMP_BIN_DIR/appimagetool"
chmod +x "$TMP_BIN_DIR/linuxdeploy" "$TMP_BIN_DIR/appimagetool"

"$TMP_BIN_DIR/linuxdeploy" --appdir "$ABS_APPDIR" --desktop-file "$ABS_APPDIR/$APP_NAME.desktop" --icon-file "$ABS_APPDIR/$APP_NAME.svg" --output appimage || true

OUT_NAME="$APP_NAME-$APP_VERSION-$ARCH.AppImage"
export APPIMAGE_EXTRACT_AND_RUN=1
ARCH="$ARCH" "$TMP_BIN_DIR/appimagetool" "$ABS_APPDIR" "$ABS_OUTPUT_DIR/$OUT_NAME"
chmod +x "$ABS_OUTPUT_DIR/$OUT_NAME"

file "$ABS_OUTPUT_DIR/$OUT_NAME"
echo "==> AppImage created: $ABS_OUTPUT_DIR/$OUT_NAME"
echo "Run it with: $ABS_OUTPUT_DIR/$OUT_NAME"
