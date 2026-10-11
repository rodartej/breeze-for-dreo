#!/bin/zsh
# Builds "Breeze for Dreo.app" into .build/
#   --universal   Apple silicon + Intel binary (used for releases)
#   --zip         also create .build/Breeze-for-Dreo-<version>.zip
#   --install     copy the app to /Applications and open it
set -euo pipefail
cd "${0:A:h}/.."

NAME="Breeze for Dreo"
BUNDLE_ID="io.github.rodartej.breeze-for-dreo"
APP=".build/$NAME.app"
universal=false; zip=false; install=false
for arg in "$@"; do
  case $arg in
    --universal) universal=true ;;
    --zip) zip=true ;;
    --install) install=true ;;
    *) echo "Unknown option: $arg" >&2; exit 64 ;;
  esac
done

mkdir -p .build
touch .build/.metadata_never_index  # keep Spotlight/Alfred from listing a second copy
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

archs=($(uname -m))
$universal && archs=(arm64 x86_64)
bins=()
for arch in $archs; do
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos15.0" \
    Sources/*.swift -o ".build/Breeze-$arch"
  bins+=(".build/Breeze-$arch")
done
lipo -create $bins -output "$APP/Contents/MacOS/Breeze"
rm -f $bins

cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built: $APP (${archs[*]})"

if $zip; then
  version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  zipfile=".build/Breeze-for-Dreo-$version.zip"
  rm -f "$zipfile"
  ditto -c -k --keepParent "$APP" "$zipfile"
  echo "Zipped: $zipfile"
fi

if $install; then
  dest="/Applications/$NAME.app"
  if [[ -d "$dest" ]] && [[ "$(defaults read "$dest/Contents/Info" CFBundleIdentifier 2>/dev/null)" != "$BUNDLE_ID" ]]; then
    echo "Another app is already at $dest; leaving it alone." >&2
    exit 1
  fi
  pkill -x Breeze 2>/dev/null && sleep 1 || true
  rm -rf "$dest"
  ditto "$APP" "$dest"
  open "$dest"
  echo "Installed: $dest"
fi
