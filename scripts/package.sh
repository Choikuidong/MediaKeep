#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
stage=$(mktemp -d "$PWD/build/stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto build/MediaKeep.app "$stage/MediaKeep.app"
ln -s /Applications "$stage/Applications"
cp INSTALL.txt "$stage/설치안내.txt"
hdiutil create -ov -fs HFS+ -volname 'MediaKeep 1.0.0' -srcfolder "$stage" -format UDZO build/MediaKeep-1.0.0-macOS-arm64.dmg
