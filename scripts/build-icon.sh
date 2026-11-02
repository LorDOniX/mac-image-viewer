#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
iconset="$PWD/.build/AppIcon.iconset"
mkdir -p "$iconset"
for logical in 16 32 128 256 512; do
    sips -z "$logical" "$logical" Resources/AppIcon.png --out "$iconset/icon_${logical}x${logical}.png" >/dev/null
    pixels=$((logical * 2))
    sips -z "$pixels" "$pixels" Resources/AppIcon.png --out "$iconset/icon_${logical}x${logical}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
