#!/bin/bash
# Builds SpaceMap.app (universal when full Xcode is installed) and SpaceMap-macOS.zip in ./build.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=SpaceMap
OUT=build
BUNDLE="$OUT/$APP.app"
rm -rf "$OUT"
mkdir -p "$OUT"

if swift build -c release --arch arm64 --arch x86_64; then
    BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
else
    echo "Universal build unavailable (Command Line Tools only?), building for this Mac"
    swift build -c release
    BIN_DIR=$(swift build -c release --show-bin-path)
fi

mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/ru.lproj"
cp "$BIN_DIR/$APP" "$BUNDLE/Contents/MacOS/$APP"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"
printf '"CFBundleDisplayName" = "SpaceMap";\n"CFBundleName" = "SpaceMap";\n' > "$BUNDLE/Contents/Resources/ru.lproj/InfoPlist.strings"

ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc signature: required to run on Apple Silicon, no developer account needed.
codesign --force --deep --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
lipo -info "$BUNDLE/Contents/MacOS/$APP"

PACKAGE="$OUT/package/SpaceMap"
mkdir -p "$PACKAGE"
ditto "$BUNDLE" "$PACKAGE/$APP.app"
cp "docs/Как запустить.txt" "$PACKAGE/"
(cd "$OUT/package" && ditto -c -k --sequesterRsrc --keepParent SpaceMap "../$APP-macOS.zip")
rm -rf "$OUT/package"
echo "Done: $BUNDLE and $OUT/$APP-macOS.zip"
