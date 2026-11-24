# -*- coding: utf-8 -*-
"""Offline test: yt-dlp must choose the matching dub, original fallback and <=4K video."""
import json,subprocess,tempfile,pathlib,sys
root=pathlib.Path(__file__).resolve().parents[1]
yt=root/'vendor/yt-dlp'
formats=[dict(format_id='v1080',url='https://example.com/v.mp4',ext='mp4',vcodec='h264',acodec='none',height=1080),dict(format_id='v2160',url='https://example.com/v4.mp4',ext='mp4',vcodec='h264',acodec='none',height=2160),dict(format_id='v4320',url='https://example.com/v8.mp4',ext='mp4',vcodec='h264',acodec='none',height=4320)]
for code,rate,note in [('ja',256,'original'),('en',128,'English dub'),('ko',96,'Korean dub')]:
 formats.append(dict(format_id=code,url='https://example.com/'+code+'.m4a',ext='m4a',vcodec='none',acodec='aac',language=code,abr=rate,format_note=note))
info=dict(id='fixture',title='Fixture',extractor='generic',webpage_url='https://example.com/fixture',formats=formats)
with tempfile.TemporaryDirectory() as d:
 file=pathlib.Path(d)/'info.json';file.write_text(json.dumps(info))
 for lang,expected in [('en','en'),('ko','ko'),('fr','ja')]:
  original='bestaudio[format_note*=original]/bestaudio/best'
  audio=f'bestaudio[language^={lang}]/best[language^={lang}]/'+original
  video=f'bv[height<=2160]+ba[language^={lang}]/b[height<=2160][language^={lang}]/bv[height<=2160]+ba[format_note*=original]/bv[height<=2160]+ba/b[height<=2160]'
  for selector,want in [(audio,expected),(video,'v2160+'+expected)]:
   out=subprocess.check_output([str(yt),'--ignore-config','--simulate','--load-info-json',str(file),'-f',selector,'--print','%(format_id)s'],text=True).strip()
   assert out==want,(selector,out,want)
print('PASS: actual yt-dlp selectors choose English/Korean dub, original fallback, and 4K ceiling without network')
