#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKOUTS_ROOT="$PIPELINE_ROOT/.work"

ARCH="${ARCH:-x86_64}"
MODE="${PIPELINE_MODE:-local}"
SKIP_UPDATE=0
VARIANT=""
SUPPORTED_VARIANTS="dnao, evilhack, nethack, all"

usage() {
  cat <<'EOF'
Standard pipeline for NetHack variants -> AppImage.

Usage:
  ./scripts/pipeline.sh [options]

Options:
  --variant <name>   Required. One of: dnao, evilhack, nethack, all
  --mode <mode>      Build mode: local or github-actions (default: local)
                     Can also be set through PIPELINE_MODE.
  --work-dir <path>  Checkout/cache directory (default: portable-nethack/.work)
  --skip-update      Do not pull latest commits before build
  --arch <arch>      AppImage arch (default: x86_64)
  -h, --help         Show this help

Examples:
  ./scripts/pipeline.sh --variant nethack
  ./scripts/pipeline.sh --variant all --mode github-actions
  ./scripts/pipeline.sh --variant evilhack --skip-update
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant)
      VARIANT="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --work-dir)
      CHECKOUTS_ROOT="${2:-}"
      shift 2
      ;;
    --skip-update)
      SKIP_UPDATE=1
      shift
      ;;
    --arch)
      ARCH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd git
need_cmd bash

source "$SCRIPT_DIR/variants.sh"

if [[ -z "$VARIANT" ]]; then
  echo "Missing required option: --variant" >&2
  usage
  exit 1
fi

case "$MODE" in
  local|github-actions)
    ;;
  *)
    echo "Invalid mode: $MODE" >&2
    echo "Supported modes: local, github-actions" >&2
    exit 1
    ;;
esac

mkdir -p "$CHECKOUTS_ROOT"

repo_dir_for_key() {
  local key="$1"
  echo "$CHECKOUTS_ROOT/$key"
}

prepare_repo() {
  local key="$1"
  local repo_url="$2"
  local branch="$3"

  local abs_repo
  abs_repo="$(repo_dir_for_key "$key")"

  if [[ ! -d "$abs_repo/.git" ]]; then
    echo "==> Cloning $key from $repo_url"
    git clone --branch "$branch" --single-branch "$repo_url" "$abs_repo"
  fi

  if [[ "$SKIP_UPDATE" -eq 1 ]]; then
    return
  fi

  pushd "$abs_repo" >/dev/null

  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Repository has local changes, skipping auto-update: $key"
    popd >/dev/null
    return
  fi

  echo "==> Updating $key ($branch)"
  git fetch origin "$branch"
  git checkout "$branch"
  git pull --ff-only origin "$branch"

  popd >/dev/null
}

out_dir_for_mode() {
  local key="$1"

  case "$MODE" in
    local)
      echo "$PIPELINE_ROOT/dist/$key"
      ;;
    github-actions)
      if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
        echo "$GITHUB_WORKSPACE/dist/$key"
      else
        echo "$PIPELINE_ROOT/dist/$key"
      fi
      ;;
  esac
}

resolve_build_script() {
  local abs_repo="$1"
  local locator="$2"

  case "$locator" in
    repo:*)
      echo "$abs_repo/${locator#repo:}"
      ;;
    pipeline:*)
      echo "$PIPELINE_ROOT/${locator#pipeline:}"
      ;;
    *)
      # Backward compatibility: treat as repo-relative path.
      echo "$abs_repo/$locator"
      ;;
  esac
}

build_variant() {
  local key="$1"
  local repo_url="$2"
  local branch="$3"
  local build_script_locator="$4"

  local abs_repo
  abs_repo="$(repo_dir_for_key "$key")"
  local build_script
  build_script="$(resolve_build_script "$abs_repo" "$build_script_locator")"

  prepare_repo "$key" "$repo_url" "$branch"

  local out_dir_abs
  out_dir_abs="$(out_dir_for_mode "$key")"
  mkdir -p "$out_dir_abs"

  if [[ ! -f "$build_script" ]]; then
    echo "Build script missing: $build_script" >&2
    exit 1
  fi

  echo "==> Building $key"
  (
    cd "$abs_repo"
    REPO_ROOT="$abs_repo" SKIP_GIT_UPDATE=1 ARCH="$ARCH" OUTPUT_DIR="$out_dir_abs" bash "$build_script"
  )

  echo "==> Finished $key"
}

run_all() {
  run_selected ""
}

run_selected() {
  local selected="$1"
  local found=0

  while IFS='|' read -r key repo_url branch build_script_rel; do
    [[ -z "$key" ]] && continue
    if [[ -n "$selected" && "$key" != "$selected" ]]; then
      continue
    fi

    found=1
    build_variant "$key" "$repo_url" "$branch" "$build_script_rel"
  done < <(list_variants)

  if [[ "$found" -ne 1 ]]; then
    echo "Unknown variant: $selected" >&2
    echo "Supported variants: $SUPPORTED_VARIANTS" >&2
    exit 1
  fi
}

case "$VARIANT" in
  all)
    run_all
    ;;
  dnao|evilhack|nethack)
    run_selected "$VARIANT"
    ;;
  *)
    echo "Invalid variant: $VARIANT" >&2
    echo "Supported variants: $SUPPORTED_VARIANTS" >&2
    exit 1
    ;;
esac

if [[ "$MODE" == "local" ]]; then
  echo "==> AppImage artifacts are under: $PIPELINE_ROOT/dist"
else
  if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    echo "==> AppImage artifacts are under: $GITHUB_WORKSPACE/dist"
  else
    echo "==> AppImage artifacts are under: $PIPELINE_ROOT/dist"
  fi
fi
