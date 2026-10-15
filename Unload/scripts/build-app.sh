#!/bin/bash
# Builds build/Unload.app. Pass --universal for an arm64 + x86_64 binary (requires Xcode).
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR=$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

APP=build/Unload.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Unload" "$APP/Contents/MacOS/Unload"
cp App/Info.plist "$APP/Contents/Info.plist"

# App icon (rendered from code; the app still builds if this step fails)
if swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null && \
   iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"; then
    echo "Generated app icon"
else
    echo "warning: could not generate the app icon" >&2
fi
rm -rf build/AppIcon.iconset

codesign --force --sign - "$APP"

echo "Built $APP"
echo "Install with: cp -R $APP /Applications/ && open /Applications/Unload.app"
