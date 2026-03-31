# portable-nethack

Standardized pipeline to update, build, and package NetHack variants as AppImage.

## Included variants

- NetHack 3.7 (`NetHack`)
- NetHack 3.6.7 (`NetHack`, branch `NetHack-3.6`)
- dNAO (`dNAO`)
- EvilHack (`EvilHack`)
- SpliceHack (`SpliceHack`)
- UnNetHack (`unnethack`)

## Quick start

From portable-nethack root:

```bash
chmod +x scripts/pipeline.sh scripts/variants.sh
./scripts/pipeline.sh --variant nethack
```

This will:

1. Clone missing upstream repositories into `portable-nethack/.work/`.
2. Pull latest commit (fast-forward only) for each clean checkout.
3. Build the selected variant with its existing variant-specific build flow.
4. Produce AppImages under `portable-nethack/dist/<variant>/` in local mode.

## Usage

```bash
./scripts/pipeline.sh --variant dnao|evilhack|nethack|nethack367|splicehack|unnethack|all [--mode local|github-actions] [--skip-update] [--arch x86_64|aarch64]
```

Examples:

```bash
./scripts/pipeline.sh --variant nethack
./scripts/pipeline.sh --variant nethack367
./scripts/pipeline.sh --variant splicehack
./scripts/pipeline.sh --variant all
./scripts/pipeline.sh --variant all --mode github-actions
./scripts/pipeline.sh --variant evilhack --skip-update
PIPELINE_MODE=github-actions ./scripts/pipeline.sh --variant dnao
ARCH=aarch64 ./scripts/pipeline.sh --variant nethack
```

## Notes

- `--variant` is required. Building all variants only happens when you explicitly pass `--variant all`.
- The pipeline is self-contained and does not depend on sibling folders. It uses upstream GitHub repositories listed in `scripts/variants.sh`.
- Variant build entrypoints can be repo-local (`repo:<path>`) or portable-nethack adapters (`pipeline:<path>`). dNAO, EvilHack, SpliceHack, UnNetHack, and NetHack currently use portable-nethack adapters because upstream branches do not ship compatible AppImage helper scripts.
- The pipeline intentionally performs a fast-forward update only. If a repo has local modifications, update is skipped for that repo.
- Variant-specific packaging is implemented in `portable-nethack/scripts/adapters/` while this repo provides one standard entrypoint and output layout.
