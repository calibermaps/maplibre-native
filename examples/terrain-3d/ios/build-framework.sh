#!/bin/bash
# Builds MapLibre.xcframework (dynamic, Metal) from this maplibre-native checkout and
# copies it next to the Xcode project. Run it from anywhere inside the checkout.
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
here="$(cd "$(dirname "$0")" && pwd)"

cd "$root"
bazel build --compilation_mode=opt --features=dead_strip,thin_lto --objc_enable_binary_stripping \
  --apple_generate_dsym --//:renderer=metal //platform/ios:MapLibre.dynamic \
  --embed_label=maplibre_ios_"$(cat platform/ios/VERSION)"

out="$(mktemp -d)"
unzip -q "$(bazel info --compilation_mode=opt bazel-bin)/platform/ios/MapLibre.dynamic.xcframework.zip" -d "$out"
rm -rf "$here/MapLibre.xcframework"
cp -R "$out/MapLibre.xcframework" "$here/MapLibre.xcframework"
rm -rf "$out"
echo "Framework ready: $here/MapLibre.xcframework"
