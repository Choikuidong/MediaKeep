"""Build on the target OS; never cross-label one platform's executable as another."""
import os,sys,hashlib,json,platform,subprocess,urllib.request,zipfile,shutil,tarfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
os.chdir(root)
assets={
 'win32':('deno-x86_64-pc-windows-msvc.zip','cba84b26e0df5ae7f74fc66b86a95b866872a86292ebd84fa1e959927edd93bf','deno.exe'),
 'linux':('deno-x86_64-unknown-linux-gnu.zip','e890975bc2549807bbcc0b584ffafda72cc7c93349dd99c80483dd784f6c4609','deno')}
if sys.platform not in assets:raise SystemExit('Use the native Swift build on macOS; run this script on Windows or Linux x64.')
machine=platform.machine().lower()
windows_arm=sys.platform=='win32' and machine in ('arm64','aarch64')
if windows_arm:
 assets['win32']=('deno-aarch64-pc-windows-msvc.zip','b413b92b735b50c198e8fe3b85af1aa50e29d5f72e229aab701d132286e14cef','deno.exe')
elif machine not in ('amd64','x86_64'):
 raise SystemExit('Use a Windows ARM64, Windows x64, or Linux x86-64 Python build.')
archive,digest,exe=assets[sys.platform];tools=root/'Resources/tools';tools.mkdir(exist_ok=True)
with urllib.request.urlopen('https://github.com/denoland/deno/releases/download/v2.9.8/'+archive,timeout=90) as r:data=r.read()
assert hashlib.sha256(data).hexdigest()==digest,'Deno checksum mismatch'
import io
with zipfile.ZipFile(io.BytesIO(data)) as z:(tools/exe).write_bytes(z.read(exe))
(tools/exe).chmod(0o755)
from PIL import Image
Image.open(root/'Resources/MediaKeep.png').save(root/'Resources/MediaKeep.ico',sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
command=[sys.executable,'-m','PyInstaller','--noconfirm','--clean','--name','MediaKeep','--onedir','--windowed','--paths','Desktop','--icon','Resources/MediaKeep.ico','--add-data','Resources'+os.pathsep+'Resources','--add-data','Licenses'+os.pathsep+'Licenses','--collect-all','yt_dlp','--collect-all','yt_dlp_ejs','--collect-all','imageio_ffmpeg','Desktop/mediakeep.py']
subprocess.run(command,check=True)
# Preserve package licenses and build provenance next to the relocatable application.
dist=root/'dist/MediaKeep'
if sys.platform=='linux':(dist/'_internal/Resources/tools/deno').chmod(0o755)
shutil.copy2(root/'INSTALL.txt',dist/'INSTALL.txt');shutil.copytree(root/'Licenses',dist/'Licenses',dirs_exist_ok=True)
import importlib.metadata
for package in ['PySide6','shiboken6','imageio-ffmpeg','yt-dlp']:
 meta=importlib.metadata.distribution(package)
 target=dist/'Licenses'/package;target.mkdir(exist_ok=True)
 for item in meta.files or []:
  if 'license' in str(item).lower() and meta.locate_file(item).is_file():
   shutil.copy2(meta.locate_file(item),target/Path(item).name)
(dist/'build-info.json').write_text(json.dumps({'version':'1.0.0','os':sys.platform,'architecture':platform.machine(),'python':platform.python_version()},indent=2))
output=root/'build';output.mkdir(exist_ok=True)
if sys.platform=='win32':
 filename=f'MediaKeep-1.0.0-Windows-{"ARM64" if windows_arm else "x64"}.zip'
 with zipfile.ZipFile(output/filename,'w',zipfile.ZIP_DEFLATED) as z:
  for path in dist.rglob('*'):
   if path.is_file():z.write(path,path.relative_to(dist.parent))
else:
 filename='MediaKeep-1.0.0-Linux-x86_64.tar.gz'
 with tarfile.open(output/filename,'w:gz') as z:z.add(dist,arcname='MediaKeep')
print(output/filename)
