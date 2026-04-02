#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Build a portable AppImage for SLASHEM Extended (SLEX).
# Required env:
#   REPO_ROOT   Path to cloned SLASHEM-Extended repository
# Optional env:
#   APP_NAME=SLEX
#   APP_VERSION=2.9.9
#   APPDIR=AppDir
#   OUTPUT_DIR=dist
#   ARCH=x86_64

APP_NAME="${APP_NAME:-SLEX}"
APP_VERSION="${APP_VERSION:-2.9.9}"
APPDIR="${APPDIR:-AppDir}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCH="${ARCH:-x86_64}"

ROOT_DIR="$(resolve_repo_root "slashem-extended")"
cd "$ROOT_DIR"

ABS_APPDIR="$ROOT_DIR/$APPDIR"
ABS_OUTPUT_DIR="$(resolve_output_dir "$ROOT_DIR" "$OUTPUT_DIR")"

need_cmds make gcc bison flex pkg-config ldd curl file awk sed grep install

mkdir -p "$ABS_OUTPUT_DIR"

if [[ ! -x ./src/slex || ! -f ./dat/nhdat ]]; then
  echo "==> Building SLASHEM Extended"
  make clean || true
  sh sys/unix/setup.sh

  # Symlink the moved yacc headers so #include "dgn.tab.h" / "lev.tab.h"
  # in the generated .c files still resolves after the Makefile moves them
  # to include/dgn_comp.h and include/lev_comp.h.
  ln -sf ../include/dgn_comp.h util/dgn.tab.h
  ln -sf ../include/lev_comp.h util/lev.tab.h

  make -f sys/unix/GNUmakefile
  make -f sys/unix/GNUmakefile install
fi

rm -rf "$ABS_APPDIR"
mkdir -p "$ABS_APPDIR/usr/bin" "$ABS_APPDIR/usr/share/$APP_NAME" "$ABS_APPDIR/usr/lib"

if [[ -x ./src/slex ]]; then
  cp ./src/slex "$ABS_APPDIR/usr/bin/slex"
else
  echo "Could not find built slex binary" >&2
  exit 1
fi

cp -a dat/nhdat dat/license dat/data dat/dungeon dat/dungeon2 dat/dungeon3 dat/dungeon4 \
      dat/dungeon5 dat/dungeon6 dat/dungeon7 dat/dungeon8 \
      dat/cmdhelp dat/dungeon.dat dat/gypsy.txt dat/help dat/hh dat/history \
      dat/opthelp dat/options dat/oracles dat/quest.dat dat/rumors dat/wizhelp \
      dat/*.lev \
      "$ABS_APPDIR/usr/share/$APP_NAME/" 2>/dev/null || true

cat > "$ABS_APPDIR/AppRun" <<EOF
#!/usr/bin/env bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
export LD_LIBRARY_PATH="\$HERE/usr/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
RUNTIME_BASE="\${XDG_DATA_HOME:-\$HOME/.local/share}"
RUNTIME_DIR="\$RUNTIME_BASE/$APP_NAME"
SEED_DIR="\$HERE/usr/share/$APP_NAME"

mkdir -p "\$RUNTIME_DIR"

if [[ ! -f "\$RUNTIME_DIR/nhdat" || ! -f "\$RUNTIME_DIR/perm" ]]; then
  cp -a "\$SEED_DIR/." "\$RUNTIME_DIR/"
fi

touch "\$RUNTIME_DIR/perm" "\$RUNTIME_DIR/record" "\$RUNTIME_DIR/logfile" "\$RUNTIME_DIR/xlogfile" "\$RUNTIME_DIR/livelog"
mkdir -p "\$RUNTIME_DIR/save" "\$RUNTIME_DIR/dumplog"
chmod u+rw "\$RUNTIME_DIR/perm" "\$RUNTIME_DIR/record" "\$RUNTIME_DIR/logfile" "\$RUNTIME_DIR/xlogfile" "\$RUNTIME_DIR/livelog" || true

cd "\$RUNTIME_DIR"
export HACKDIR="\$RUNTIME_DIR"
exec "\$HERE/usr/bin/slex" -d "\$RUNTIME_DIR" "\$@"
EOF
chmod +x "$ABS_APPDIR/AppRun"

cat > "$ABS_APPDIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SLASHEM Extended
GenericName=Roguelike Game
Comment=SLASHEM Extended variant
Exec=slex
Icon=$APP_NAME
Terminal=true
Categories=Game;RolePlaying;
EOF

cat > "$ABS_APPDIR/$APP_NAME.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" fill="#101820"/>
  <rect x="16" y="16" width="224" height="224" fill="#1f2937" stroke="#f59e0b" stroke-width="8"/>
  <text x="128" y="142" text-anchor="middle" fill="#f59e0b" font-family="monospace" font-size="84" font-weight="700">SX</text>
</svg>
EOF

copy_needed_libs "$ABS_APPDIR" "$ABS_APPDIR/usr/bin/slex"
patch_rpath_if_available "$ABS_APPDIR/usr/bin/slex"

download_appimage_tools "$ARCH"
build_appimage "$ABS_APPDIR" "$ABS_OUTPUT_DIR" "$APP_NAME" "$APP_VERSION" "$ARCH" "$ABS_APPDIR/$APP_NAME.desktop" "$ABS_APPDIR/$APP_NAME.svg"
