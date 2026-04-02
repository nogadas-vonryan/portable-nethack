#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Build a portable AppImage for HackEM using an upstream clone as source.
# Required env:
# REPO_ROOT Path to cloned HackEM repository
# Optional env:
# APP_NAME=HackEM
# APP_VERSION=1.2.2
# APPDIR=AppDir
# OUTPUT_DIR=dist
# ARCH=x86_64

APP_NAME="${APP_NAME:-HackEM}"
APP_VERSION="${APP_VERSION:-1.2.2}"
APPDIR="${APPDIR:-AppDir}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCH="${ARCH:-x86_64}"

ROOT_DIR="$(resolve_repo_root "hackem")"
cd "$ROOT_DIR"

ABS_APPDIR="$ROOT_DIR/$APPDIR"
ABS_OUTPUT_DIR="$(resolve_output_dir "$ROOT_DIR" "$OUTPUT_DIR")"

need_cmds make gcc pkg-config ldd curl file awk sed grep install gzip

TERM_LIBS=""
if pkg-config --exists ncursesw; then
  TERM_LIBS="$(pkg-config --libs ncursesw)"
elif pkg-config --exists ncurses; then
  TERM_LIBS="$(pkg-config --libs ncurses)"
else
  TERM_LIBS="-lncurses -ltinfo"
fi
echo "==> Using terminal libs: $TERM_LIBS"

GZIP_PATH="$(command -v gzip)"
echo "==> Using savefile compressor: $GZIP_PATH"
sed -i "s|^#define COMPRESS \"/usr/bin/compress\".*|#define COMPRESS \"$GZIP_PATH\" /* gzip compression */|" include/config.h
sed -i 's|^#define COMPRESS_EXTENSION "\.Z".*|#define COMPRESS_EXTENSION ".gz" /* gzip extension */|' include/config.h

MAKE_VARS=(WINTTYLIB="$TERM_LIBS" WINLIB="$TERM_LIBS" CPPFLAGS="${CPPFLAGS:-} -DDUMPLOG")
mkdir -p "$ABS_OUTPUT_DIR"

echo "==> Running setup.sh sys/unix/hints/unix to distribute Makefiles"
sh sys/unix/setup.sh sys/unix/hints/unix

echo "==> Enabling DUMPLOG for HackEM link consistency"

echo "==> Building HackEM (top-level make all)"
make "${MAKE_VARS[@]}" all

rm -rf "$ABS_APPDIR"
mkdir -p "$ABS_APPDIR/usr/bin" "$ABS_APPDIR/usr/share/$APP_NAME" "$ABS_APPDIR/usr/lib"

echo "==> Installing into AppDir"
make install \
  HACKDIR="$ABS_APPDIR/usr/share/$APP_NAME" \
  VARDIR="$ABS_APPDIR/usr/share/$APP_NAME" \
  SHELLDIR="$ABS_APPDIR/usr/bin" \
  CHOWN=true CHGRP=true GAMEPERM=0755 \
  "${MAKE_VARS[@]}"

if [[ -x "$ROOT_DIR/src/hackem" ]]; then
  cp "$ROOT_DIR/src/hackem" "$ABS_APPDIR/usr/bin/hackem-bin"
elif [[ -x "$ABS_APPDIR/usr/share/$APP_NAME/hackem" ]]; then
  cp "$ABS_APPDIR/usr/share/$APP_NAME/hackem" "$ABS_APPDIR/usr/bin/hackem-bin"
else
  echo "Could not find built hackem binary" >&2
  exit 1
fi

cat > "$ABS_APPDIR/AppRun" <<EOF
#!/usr/bin/env bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
export LD_LIBRARY_PATH="\$HERE/usr/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
RUNTIME_BASE="\${XDG_DATA_HOME:-\$HOME/.local/share}"
RUNTIME_DIR="\$RUNTIME_BASE/HackEM-AppImage"
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
exec "\$HERE/usr/bin/hackem-bin" -d "\$RUNTIME_DIR" "\$@"
EOF
chmod +x "$ABS_APPDIR/AppRun"

cat > "$ABS_APPDIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=HackEM
GenericName=Roguelike Game
Comment=HackEM NetHack variant
Exec=hackem-bin
Icon=$APP_NAME
Terminal=true
Categories=Game;RolePlaying;
EOF

cat > "$ABS_APPDIR/$APP_NAME.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<rect width="256" height="256" fill="#13181f"/>
<rect x="16" y="16" width="224" height="224" fill="#1d2838" stroke="#d97706" stroke-width="8"/>
<text x="128" y="142" text-anchor="middle" fill="#f59e0b" font-family="monospace" font-size="72" font-weight="700">HM</text>
</svg>
EOF

copy_needed_libs "$ABS_APPDIR" "$ABS_APPDIR/usr/bin/hackem-bin"
patch_rpath_if_available "$ABS_APPDIR/usr/bin/hackem-bin"

download_appimage_tools "$ARCH"
build_appimage "$ABS_APPDIR" "$ABS_OUTPUT_DIR" "$APP_NAME" "$APP_VERSION" "$ARCH" "$ABS_APPDIR/$APP_NAME.desktop" "$ABS_APPDIR/$APP_NAME.svg"