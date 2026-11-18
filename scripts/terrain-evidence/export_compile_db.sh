#!/usr/bin/env bash
# Copy the Linux compile database out of the ml-build container and point it at
# this checkout, for clangd on the host. Usage, from the repo root:
#   scripts/terrain-evidence/export_compile_db.sh [container tree] [build dir]
set -euo pipefail
TREE=${1:-/work/src-phase0}
BUILD=${2:-build-rt}
HERE=$(pwd)
docker exec ml-build cat "$TREE/$BUILD/compile_commands.json" \
  | sed -e "s#$TREE/$BUILD#$HERE/.cache/linux-build#g" -e "s#$TREE#$HERE#g" > compile_commands.json
# Generated headers live only in the container build folder; copy them next to the checkout.
mkdir -p .cache/linux-build
docker exec ml-build bash -c "cd '$TREE/$BUILD' && find . -name '*.hpp' -o -name '*.h' | tar -cf - -T -" | tar -xf - -C .cache/linux-build
# Submodule headers, for checkouts without the submodules (the container tree has them).
docker exec ml-build bash -c "cd '$TREE' && for p in vendor/*/; do [ -n \"\$(ls -A \"\$p\" 2>/dev/null)\" ] && echo \"\$p\"; done \
  | xargs -I{} find {} -type f \( -name '*.h' -o -name '*.hpp' -o -name '*.hh' -o -name '*.inl' -o -name '*.ipp' \) \
  | tar -cf - -T -" | tar -xkf - 2>/dev/null || true
echo "$(grep -c '"file"' compile_commands.json) entries"
