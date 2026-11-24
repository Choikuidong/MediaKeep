#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x vendor/ffmpeg || ! -x vendor/yt-dlp || ! -x vendor/deno ]]; then bash scripts/fetch-tools.sh; fi
app=build/MediaKeep.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/"
cp Resources/Translations.json Resources/MediaKeep.png Resources/AppleCraftSymbol.png Resources/AppIcon.icns vendor/{ffmpeg,yt-dlp,deno} "$app/Contents/Resources/"
ditto Licenses "$app/Contents/Resources/Licenses"
swiftc -O -target arm64-apple-macos13.0 Sources/*.swift -o "$app/Contents/MacOS/VideoToMP3"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/VideoToMP3" --self-test
