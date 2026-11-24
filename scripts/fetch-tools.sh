#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p vendor build/cache
cache=build/cache
fetch() { if [[ ! -f "$2" ]]; then curl -fsSL --retry 2 "$1" -o "$2.part"; mv "$2.part" "$2"; fi; }
fetch https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/yt-dlp_macos "$cache/yt-dlp"
fetch https://github.com/denoland/deno/releases/download/v2.9.8/deno-aarch64-apple-darwin.zip "$cache/deno.zip"
python3 - <<'PY'
import json,urllib.request,pathlib,hashlib,zipfile
cache=pathlib.Path('build/cache')
with urllib.request.urlopen('https://pypi.org/pypi/imageio-ffmpeg/0.6.0/json') as response:
    entry=next(x for x in json.load(response)['urls'] if x['filename'].endswith('macosx_11_0_arm64.whl'))
wheel=cache/entry['filename']
if not wheel.exists(): urllib.request.urlretrieve(entry['url'],wheel)
assert hashlib.sha256(wheel.read_bytes()).hexdigest()==entry['digests']['sha256']
with zipfile.ZipFile(wheel) as z: pathlib.Path('vendor/ffmpeg').write_bytes(z.read(next(n for n in z.namelist() if '/binaries/ffmpeg-' in n)))
PY
(cd "$cache" && shasum -a 256 -c ../../Resources/downloads.sha256)
unzip -p "$cache/deno.zip" deno > vendor/deno
cp "$cache/yt-dlp" vendor/yt-dlp
chmod 755 vendor/{yt-dlp,ffmpeg,deno}
