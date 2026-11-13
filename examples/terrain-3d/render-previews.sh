#!/usr/bin/env bash
# Render every example (or the ones named) to previews/NN-name.png with mbgl-render.
#   ./render-previews.sh            all still examples
#   ./render-previews.sh 03 05      only these
# Environment: MBGL_RENDER (path to mbgl-render), WIDTH, HEIGHT, CACHE (network cache file).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
ensure_display "$0" "$@"

RENDER="$(find_tool mbgl-render MBGL_RENDER || true)"
if [ -z "$RENDER" ]; then
    echo "mbgl-render not found. Build it first:" >&2
    echo "  cmake --preset linux-opengl && cmake --build build-linux-opengl --target mbgl-render" >&2
    exit 1
fi
CACHE="${CACHE:-${TMPDIR:-/tmp}/terrain-3d-examples-cache.sqlite}"
mkdir -p "$HERE/previews"

if [ $# -gt 0 ]; then
    NAMES=(); for a in "$@"; do resolve_example "$a"; NAMES+=("$NAME"); done
else
    NAMES=(); while read -r n; do NAMES+=("$n"); done < <(awk '!/^#/ && NF {print $1}' "$HERE/cameras.txt")
fi

for n in "${NAMES[@]}"; do
    echo "== $n"
    render_still "$n" "$HERE/previews/$n.png" "${WIDTH:-720}" "${HEIGHT:-450}"
    python3 "$HERE/lib/shrink_png.py" "$HERE/previews/$n.png"
done
