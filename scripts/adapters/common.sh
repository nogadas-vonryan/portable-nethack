#!/usr/bin/env bash

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmds() {
  local cmd
  for cmd in "$@"; do
    need_cmd "$cmd"
  done
}

resolve_repo_root() {
  local key="$1"

  if [[ -n "${REPO_ROOT:-}" ]]; then
    echo "$REPO_ROOT"
  else
    echo "$(cd "$(dirname "${BASH_SOURCE[1]}")/../.." && pwd)/.work/$key"
  fi
}

resolve_output_dir() {
  local root_dir="$1"
  local output_dir="$2"

  case "$output_dir" in
    /*)
      echo "$output_dir"
      ;;
    *)
      echo "$root_dir/$output_dir"
      ;;
  esac
}

create_tool_bin_dir() {
  TMP_BIN_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_BIN_DIR"' EXIT
}

set_appimage_urls() {
  local arch="$1"

  case "$arch" in
    x86_64)
      LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${arch}.AppImage"
      APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${arch}.AppImage"
      ;;
    aarch64)
      LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${arch}.AppImage"
      APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-aarch64.AppImage"
      ;;
    *)
      echo "Unsupported ARCH: $arch" >&2
      exit 1
      ;;
  esac
}

download_appimage_tools() {
  local arch="$1"

  create_tool_bin_dir
  set_appimage_urls "$arch"

  echo "==> Downloading linuxdeploy + appimagetool"
  curl -fsSL "$LINUXDEPLOY_URL" -o "$TMP_BIN_DIR/linuxdeploy"
  curl -fsSL "$APPIMAGETOOL_URL" -o "$TMP_BIN_DIR/appimagetool"
  chmod +x "$TMP_BIN_DIR/linuxdeploy" "$TMP_BIN_DIR/appimagetool"
}

copy_needed_libs() {
  local appdir="$1"
  shift

  local bin
  for bin in "$@"; do
    if [[ ! -e "$bin" ]]; then
      echo "Warning: binary not found for dependency scan: $bin" >&2
      continue
    fi

    local ldd_output
    if ! ldd_output="$(ldd "$bin" 2>&1)"; then
      if printf '%s\n' "$ldd_output" | grep -Eq 'not a dynamic executable|statically linked'; then
        echo "==> Skipping shared library copy for static binary: $bin"
        continue
      fi
      echo "Warning: ldd failed for $bin; skipping dependency copy" >&2
      continue
    fi

    printf '%s\n' "$ldd_output" | awk '/=> \/|^\// { for (i=1; i<=NF; ++i) if ($i ~ /^\//) print $i }' | while IFS= read -r lib; do
      [[ -z "$lib" ]] && continue

      local base
      base="$(basename "$lib")"
      case "$base" in
        linux-vdso.so.*|ld-linux*.so*|libc.so.*|libm.so.*|libpthread.so.*|librt.so.*|libdl.so.*|libutil.so.*|libresolv.so.*)
          continue
          ;;
      esac

      if [[ ! -e "$appdir/usr/lib/$base" ]]; then
        cp -a "$lib" "$appdir/usr/lib/"
      fi
    done
  done
}

patch_rpath_if_available() {
  local bin="$1"

  if command -v patchelf >/dev/null 2>&1; then
    patchelf --set-rpath '$ORIGIN/../lib' "$bin" || true
  else
    echo "patchelf not found; skipping RPATH patch (LD_LIBRARY_PATH in AppRun still handles runtime)"
  fi
}

build_appimage() {
  local appdir="$1"
  local output_dir="$2"
  local app_name="$3"
  local app_version="$4"
  local arch="$5"
  local desktop_file="$6"
  local icon_file="$7"

  "$TMP_BIN_DIR/linuxdeploy" --appdir "$appdir" --desktop-file "$desktop_file" --icon-file "$icon_file" --output appimage || true

  local out_name
  out_name="$app_name-$app_version-$arch.AppImage"

  export APPIMAGE_EXTRACT_AND_RUN=1
  ARCH="$arch" "$TMP_BIN_DIR/appimagetool" "$appdir" "$output_dir/$out_name"
  chmod +x "$output_dir/$out_name"

  file "$output_dir/$out_name"
  echo "==> AppImage created: $output_dir/$out_name"
  echo "Run it with: $output_dir/$out_name"
}
