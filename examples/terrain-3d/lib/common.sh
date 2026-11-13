# Shared helpers, sourced by run.sh, render-previews.sh and tour.sh.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # examples/terrain-3d
REPO="$(cd "$HERE/../.." && pwd)"                        # repository root

# resolve_example <number|name|prefix>  ->  sets NAME (e.g. 03-vector-basemap)
resolve_example() {
    local want="$1" hit
    hit="$(awk -v w="$want" '!/^#/ && NF && (index($1, w) == 1 || index($1, "-" w) > 0) {print $1}' "$HERE/cameras.txt" | head -n 1)"
    if [ -z "$hit" ]; then
        echo "Unknown example '$want'. Available:" >&2
        awk '!/^#/ && NF {print "  " $1}' "$HERE/cameras.txt" >&2
        return 1
    fi
    NAME="$hit"
}

# camera_of <name>  ->  sets LON LAT ZOOM PITCH BEARING ALT
camera_of() {
    read -r _ LON LAT ZOOM PITCH BEARING ALT < <(awk -v n="$1" '$1 == n {print}' "$HERE/cameras.txt")
}

# Find mbgl-render / mbgl-glfw. Override with MBGL_RENDER / MBGL_GLFW.
find_tool() {
    local tool="$1" var="$2" dir
    if [ -n "${!var:-}" ]; then echo "${!var}"; return; fi
    for dir in build-linux-opengl build build-gl; do
        for sub in bin platform/glfw; do
            [ -x "$REPO/$dir/$sub/$tool" ] && { echo "$REPO/$dir/$sub/$tool"; return; }
        done
    done
    return 1
}

# ensure_display "$0" "$@": on headless Linux, re-run the calling script under a virtual X server.
ensure_display() {
    if [ "$(uname)" = "Linux" ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${TERRAIN_EXAMPLES_IN_XVFB:-}" ] && command -v xvfb-run >/dev/null; then
        TERRAIN_EXAMPLES_IN_XVFB=1 exec xvfb-run -a "$@"
    fi
}

# render_camera <style.json> <out.png> <width> <height> <lon> <lat> <zoom> <pitch> <bearing> <centerAltitude>
# Runs mbgl-render once for that camera. The tile servers occasionally drop a connection (or the virtual
# display is not ready) and mbgl-render then exits without an image. Tiles already fetched stay in the
# cache, so trying again continues where the last attempt stopped.
render_camera() {
    local style="$1" out="$2" w="$3" h="$4" lon="$5" lat="$6" zoom="$7" pitch="$8" bearing="$9" alt="${10}" attempt
    rm -f "$out"
    for attempt in 1 2 3 4 5 6 7 8; do
        "$RENDER" --style "file://$style" --lon "$lon" --lat "$lat" --zoom "$zoom" --pitch "$pitch" --bearing "$bearing" \
            --alt "$alt" --width "$w" --height "$h" --cache "$CACHE" --output "$out" 2>&1 | grep -v -E 'libEGL|GPU Identifier' || true
        [ -s "$out" ] && return 0
        echo "  attempt $attempt gave no image, retrying" >&2
    done
    return 1
}

# render_still <example-name> <out.png> [width] [height]: the example at its camera from cameras.txt.
render_still() {
    local name="$1"
    camera_of "$name"
    render_camera "$HERE/styles/$name.json" "$2" "${3:-720}" "${4:-450}" "$LON" "$LAT" "$ZOOM" "$PITCH" "$BEARING" "$ALT"
}
