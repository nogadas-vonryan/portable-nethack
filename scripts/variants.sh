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
hackem|https://github.com/elunna/hackem.git|master|pipeline:scripts/adapters/build_appimage_hackem.sh
nethack|https://github.com/NetHack/NetHack.git|NetHack-3.7|pipeline:scripts/adapters/build_appimage_nethack.sh
nethack367|https://github.com/NetHack/NetHack.git|NetHack-3.6|pipeline:scripts/adapters/build_appimage_nethack367.sh
sil-q|https://github.com/sil-quirk/sil-q.git|master|pipeline:scripts/adapters/build_appimage_sil_q.sh
slashem-extended|https://github.com/SLASHEM-Extended/SLASHEM-Extended.git|master|pipeline:scripts/adapters/build_appimage_slashem_extended.sh
splicehack|https://github.com/k21971/SpliceHack.git|master|pipeline:scripts/adapters/build_appimage_splicehack.sh
unnethack|https://github.com/UnNetHack/UnNetHack.git|master|pipeline:scripts/adapters/build_appimage_unnethack.sh
EOF
}
