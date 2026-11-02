#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
if [[ ! -f Resources/AppIcon.icns || Resources/AppIcon.png -nt Resources/AppIcon.icns || scripts/build-icon.sh -nt Resources/AppIcon.icns ]]; then
    zsh scripts/build-icon.sh
fi
swift build -c release --build-system native --disable-sandbox --cache-path "$PWD/.build/cache"
bin_dir="$(swift build -c release --build-system native --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache")"
app="$PWD/dist/Image Viewer.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/ImageViewer" "$app/Contents/MacOS/ImageViewer"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
# Finder watches the application bundle itself, whose modification date does
# not otherwise change when only files inside Contents are replaced.
touch "$app"
printf 'Hotovo: %s\n' "$app"
