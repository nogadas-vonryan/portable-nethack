#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Build a portable AppImage for dNAO (dnethack) using an upstream clone as source.
# Required env:
#   REPO_ROOT   Path to cloned dNAO repository
# Optional env:
#   APP_NAME=dNAO
#   APP_VERSION=3.25.0
#   APPDIR=AppDir
#   OUTPUT_DIR=dist
#   ARCH=x86_64

APP_NAME="${APP_NAME:-dNAO}"
APP_VERSION="${APP_VERSION:-3.25.0}"
APPDIR="${APPDIR:-AppDir}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCH="${ARCH:-x86_64}"

ROOT_DIR="$(resolve_repo_root "dnao")"
cd "$ROOT_DIR"

ABS_APPDIR="$ROOT_DIR/$APPDIR"
ABS_OUTPUT_DIR="$(resolve_output_dir "$ROOT_DIR" "$OUTPUT_DIR")"

need_cmds make gcc bison flex pkg-config ldd curl file awk sed grep install
mkdir -p "$ABS_OUTPUT_DIR"

if [[ ! -x ./src/dnethack || ! -f ./dat/nhdat || ! -d ./dnethackdir ]]; then
  echo "==> Building dNAO"
  make clean || true
  make install
fi

if [[ ! -d dnethackdir ]]; then
  echo "Expected dnethackdir after make install, but it does not exist" >&2
  exit 1
fi

rm -rf "$ABS_APPDIR"
mkdir -p "$ABS_APPDIR/usr/bin" "$ABS_APPDIR/usr/share/$APP_NAME" "$ABS_APPDIR/usr/lib"

cp -a dnethackdir/. "$ABS_APPDIR/usr/share/$APP_NAME/"
cp -a src/dnethack "$ABS_APPDIR/usr/bin/dnethack"

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
exec "\$HERE/usr/bin/dnethack" "\$@"
EOF
chmod +x "$ABS_APPDIR/AppRun"

cat > "$ABS_APPDIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=dNAO
GenericName=Roguelike Game
Comment=dNetHack variant
Exec=dnethack
Icon=$APP_NAME
Terminal=true
Categories=Game;RolePlaying;
EOF

cat > "$ABS_APPDIR/$APP_NAME.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" fill="#101820"/>
  <rect x="16" y="16" width="224" height="224" fill="#1f2937" stroke="#f59e0b" stroke-width="8"/>
  <text x="128" y="142" text-anchor="middle" fill="#f59e0b" font-family="monospace" font-size="84" font-weight="700">dN</text>
</svg>
EOF

copy_needed_libs "$ABS_APPDIR" "src/dnethack" "util/recover"
patch_rpath_if_available "$ABS_APPDIR/usr/bin/dnethack"

download_appimage_tools "$ARCH"
build_appimage "$ABS_APPDIR" "$ABS_OUTPUT_DIR" "$APP_NAME" "$APP_VERSION" "$ARCH" "$ABS_APPDIR/$APP_NAME.desktop" "$ABS_APPDIR/$APP_NAME.svg"
