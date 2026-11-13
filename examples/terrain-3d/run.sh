#!/usr/bin/env bash
# Open one terrain example in the interactive GLFW viewer, at its camera.
#   ./run.sh <example>        e.g. ./run.sh 03   or   ./run.sh vector-basemap
# Linux: builds mbgl-glfw with the linux-opengl CMake preset if it is not built yet.
# macOS: runs it through Bazel with the Metal renderer (see docs/mdbook/src/platforms/macos/README.md).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if [ $# -ne 1 ]; then
    echo "usage: $0 <example>" >&2
    awk '!/^#/ && NF {print "  " $1}' "$HERE/cameras.txt" >&2
    exit 2
fi
resolve_example "$1"
camera_of "$NAME"
STYLE="file://$HERE/styles/$NAME.json"
ARGS=(--style "$STYLE" --lon "$LON" --lat "$LAT" --zoom "$ZOOM" --pitch "$PITCH" --bearing "$BEARING" --alt "$ALT" --maxPitch 85)
echo "Example $NAME: lon=$LON lat=$LAT zoom=$ZOOM pitch=$PITCH bearing=$BEARING centerAltitude=${ALT}m"

cd "$REPO"
if [ "$(uname)" = "Darwin" ]; then
    RENDERER="${RENDERER:-metal}"
    if [ "$NAME" = "06-buildings" ] && [ "$RENDERER" != "opengl" ]; then
        echo "Note: fill-extrusion height on terrain is documented for OpenGL and WebGPU only so far (TERRAIN.md)." >&2
    fi
    exec bazel run "--//:renderer=$RENDERER" //platform/glfw:glfw_app -- "${ARGS[@]}"
fi

GLFW="$(find_tool mbgl-glfw MBGL_GLFW || true)"
if [ -z "$GLFW" ]; then
    cmake --preset linux-opengl
    cmake --build build-linux-opengl --target mbgl-glfw
    GLFW="$(find_tool mbgl-glfw MBGL_GLFW)"
fi
exec "$GLFW" "${ARGS[@]}"
