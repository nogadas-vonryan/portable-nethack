#!/usr/bin/env bash

# Variant registry for portable-nethack pipeline.
# Format:
#   key|repo_url|branch|build_script_locator
#
# build_script_locator supports:
#   repo:<path>      Path inside cloned repo
#   pipeline:<path>  Path inside portable-nethack root

list_variants() {
  cat <<'EOF'
dnao|https://github.com/Chris-plus-alphanumericgibberish/dNAO.git|compat-3.25.0|pipeline:scripts/adapters/build_appimage_dnao.sh
evilhack|https://github.com/k21971/EvilHack.git|master|pipeline:scripts/adapters/build_appimage_evilhack.sh
nethack|https://github.com/NetHack/NetHack.git|NetHack-3.7|pipeline:scripts/adapters/build_appimage_nethack.sh
nethack367|https://github.com/NetHack/NetHack.git|NetHack-3.6|pipeline:scripts/adapters/build_appimage_nethack367.sh
EOF
}
