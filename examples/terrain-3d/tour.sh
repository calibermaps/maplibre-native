#!/usr/bin/env bash
# Render the camera tour (tour.txt) frame by frame and stitch the frames into previews/07-camera-tour.gif.
# Uses ffmpeg when it is installed, otherwise Pillow. Prints the camera clearance above ground per frame.
# Environment: MBGL_RENDER, FRAMES_PER_SEGMENT (default 4), FPS (default 8), WIDTH, HEIGHT, CACHE, KEEP_FRAMES=1.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
ensure_display "$0" "$@"

RENDER="$(find_tool mbgl-render MBGL_RENDER || true)"
[ -n "$RENDER" ] || { echo "mbgl-render not found (see README)." >&2; exit 1; }
STYLE_NAME="02-hillshade-color-relief"
STYLE="$HERE/styles/$STYLE_NAME.json"
W="${WIDTH:-440}"; H="${HEIGHT:-275}"; FPS="${FPS:-8}"
CACHE="${CACHE:-${TMPDIR:-/tmp}/terrain-3d-examples-cache.sqlite}"
OUT="$HERE/previews/07-camera-tour.gif"
FRAMES="$(mktemp -d)"
[ -n "${KEEP_FRAMES:-}" ] || trap 'rm -rf "$FRAMES"' EXIT
mkdir -p "$HERE/previews"

if ! python3 "$HERE/lib/tour_frames.py" "$STYLE" "$HERE/tour.txt" "${FRAMES_PER_SEGMENT:-4}" 120 "$W" "$H" > "$FRAMES/frames.txt" 2> "$FRAMES/clearance.txt"; then
    tail -n 1 "$FRAMES/clearance.txt" >&2
    echo "The camera would come too close to the ground. Edit tour.txt." >&2
    exit 1
fi
tail -n 1 "$FRAMES/clearance.txt"

while read -r idx lon lat zoom pitch bearing alt; do
    printf 'frame %s\n' "$idx"
    render_camera "$STYLE" "$FRAMES/f$(printf %03d "$idx").png" "$W" "$H" "$lon" "$lat" "$zoom" "$pitch" "$bearing" "$alt"
done < "$FRAMES/frames.txt"

if command -v ffmpeg >/dev/null; then
    ffmpeg -loglevel error -y -framerate "$FPS" -i "$FRAMES/f%03d.png" \
        -vf "split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$OUT"
else
    echo "ffmpeg not found, stitching with Pillow" >&2
    python3 - "$FRAMES" "$OUT" "$FPS" <<'PY'
import glob, sys
from PIL import Image
frames = sorted(glob.glob(sys.argv[1] + "/f*.png"))
imgs = [Image.open(f).convert("RGB").quantize(48, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE) for f in frames]
imgs[0].save(sys.argv[2], save_all=True, append_images=imgs[1:], duration=int(1000 / int(sys.argv[3])), loop=0, optimize=True)
PY
fi
echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
