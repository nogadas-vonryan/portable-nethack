#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Build a portable AppImage for Sil-Q using an upstream clone as source.
# Required env:
#   REPO_ROOT   Path to cloned Sil-Q repository
# Optional env:
#   APP_NAME=Sil-Q
#   APP_VERSION=<auto-detected from CMakeLists.txt, fallback: main>
#   APPDIR=AppDir
#   OUTPUT_DIR=dist
#   ARCH=x86_64

APP_NAME="${APP_NAME:-Sil-Q}"
APPDIR="${APPDIR:-AppDir}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCH="${ARCH:-x86_64}"

ROOT_DIR="$(resolve_repo_root "sil-q")"
cd "$ROOT_DIR"

detect_version() {
  local detected
  detected="$(sed -nE 's/^project\(Sil-Q VERSION ([0-9]+\.[0-9]+\.[0-9]+).*$/\1/p' CMakeLists.txt | head -n 1 || true)"
  if [[ -n "$detected" ]]; then
    printf '%s\n' "$detected"
  else
    printf '%s\n' "main"
  fi
}

APP_VERSION="${APP_VERSION:-$(detect_version)}"

ABS_APPDIR="$ROOT_DIR/$APPDIR"
ABS_OUTPUT_DIR="$(resolve_output_dir "$ROOT_DIR" "$OUTPUT_DIR")"

need_cmds cmake gcc pkg-config ldd curl file awk sed grep install

NINJA_CMD=""
if command -v ninja >/dev/null 2>&1; then
  NINJA_CMD="ninja"
elif command -v ninja-build >/dev/null 2>&1; then
  NINJA_CMD="ninja-build"
else
  echo "Missing required command: ninja (or ninja-build)" >&2
  exit 1
fi

mkdir -p "$ABS_OUTPUT_DIR"

echo "==> Building Sil-Q (GCU frontend)"
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_MAKE_PROGRAM="$NINJA_CMD" -DSUPPORT_X11_FRONTEND=OFF -DSUPPORT_COCOA_FRONTEND=OFF
cmake --build build

if [[ ! -x "$ROOT_DIR/build/sil" ]]; then
  echo "Could not find built sil binary at build/sil" >&2
  exit 1
fi

rm -rf "$ABS_APPDIR"
mkdir -p "$ABS_APPDIR/usr/bin" "$ABS_APPDIR/usr/share/$APP_NAME" "$ABS_APPDIR/usr/lib"

cp "$ROOT_DIR/build/sil" "$ABS_APPDIR/usr/bin/sil-bin"
cp -a "$ROOT_DIR/lib" "$ABS_APPDIR/usr/share/$APP_NAME/lib"

cat > "$ABS_APPDIR/AppRun" <<EOF
#!/usr/bin/env bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
export LD_LIBRARY_PATH="\$HERE/usr/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
RUNTIME_BASE="\${XDG_DATA_HOME:-\$HOME/.local/share}"
RUNTIME_DIR="\$RUNTIME_BASE/Sil-Q-AppImage"
SEED_DIR="\$HERE/usr/share/$APP_NAME"

mkdir -p "\$RUNTIME_DIR"

if [[ ! -d "\$RUNTIME_DIR/lib" ]]; then
  cp -a "\$SEED_DIR/lib" "\$RUNTIME_DIR/lib"
fi

mkdir -p "\$RUNTIME_DIR/lib/save" "\$RUNTIME_DIR/lib/user"

cd "\$RUNTIME_DIR"
export ANGBAND_PATH="\$RUNTIME_DIR"
exec "\$HERE/usr/bin/sil-bin" "\$@"
EOF
chmod +x "$ABS_APPDIR/AppRun"

cat > "$ABS_APPDIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Sil-Q
GenericName=Roguelike Game
Comment=Sil-Q roguelike
Exec=sil-bin
Icon=$APP_NAME
Terminal=true
Categories=Game;RolePlaying;
EOF

cat > "$ABS_APPDIR/$APP_NAME.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" fill="#111827"/>
  <rect x="16" y="16" width="224" height="224" fill="#1f2937" stroke="#34d399" stroke-width="8"/>
  <text x="128" y="142" text-anchor="middle" fill="#34d399" font-family="monospace" font-size="72" font-weight="700">SQ</text>
</svg>
EOF

copy_needed_libs "$ABS_APPDIR" "$ABS_APPDIR/usr/bin/sil-bin"
patch_rpath_if_available "$ABS_APPDIR/usr/bin/sil-bin"

download_appimage_tools "$ARCH"
build_appimage "$ABS_APPDIR" "$ABS_OUTPUT_DIR" "$APP_NAME" "$APP_VERSION" "$ARCH" "$ABS_APPDIR/$APP_NAME.desktop" "$ABS_APPDIR/$APP_NAME.svg"
