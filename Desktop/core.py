"""Shared media operations. No GUI dependencies; source files are never modified."""
from __future__ import annotations
import json, os, re, sys, shutil, subprocess, tempfile, threading, urllib.parse, urllib.request
from dataclasses import dataclass
from pathlib import Path

VERSION='1.0.0'
REPOSITORY='Choikuidong/MediaKeep'
RESOURCE=Path(getattr(sys,'_MEIPASS',Path(__file__).resolve().parents[1]))/'Resources'
if not RESOURCE.exists(): RESOURCE=Path(__file__).resolve().parents[1]/'Resources'
LANGUAGES=json.loads((RESOURCE/'Languages.json').read_text(encoding='utf-8'))
STRINGS=json.loads((RESOURCE/'Strings.json').read_text(encoding='utf-8'))
class Cancelled(Exception): pass

def tr(key,language='en'):
    return STRINGS.get(language,{}).get(key,key)

def language(code):
    return next((v for v in LANGUAGES if v['code']==code),LANGUAGES[0])

def parse_time(text):
    pieces=text.strip().split(':')
    if not 1<=len(pieces)<=3: raise ValueError('Check the start and end times.')
    result=0.0
    for i,value in enumerate(pieces):
        if not re.fullmatch(r'\d+(?:\.\d+)?',value):raise ValueError('Check the start and end times.')
        n=float(value)
        if (i and n>=60) or n>315360000:raise ValueError('Check the start and end times.')
        result=result*60+n
    return result

def clean_name(text):
    name=re.sub(r'[<>:"/\\|?*\x00-\x1f]',' ',text).strip(' .')
    while len(name.encode('utf-8'))>180:name=name[:-1]
    if not name:name='MediaKeep'
    if name.split('.')[0].upper() in {'CON','PRN','AUX','NUL',*[f'COM{i}' for i in range(1,10)],*[f'LPT{i}' for i in range(1,10)]}:name='_'+name
    return name

def audio_format(code):
    if not code:return 'bestaudio[format_note*=original]/bestaudio/best'
    codes=list(dict.fromkeys([code,code.split('-')[0]]))
    return '/'.join(f'bestaudio[language^={x}]/best[language^={x}]' for x in codes)+'/bestaudio[format_note*=original]/bestaudio/best'

def video_format(height,code):
    v=f'bv[height<={height}]';b=f'b[height<={height}]'
    preferences=[]
    if code:
        for c in dict.fromkeys([code,code.split('-')[0]]):preferences += [f'{v}+ba[language^={c}]',f'{b}[language^={c}]']
    return '/'.join(preferences+[f'{v}+ba[format_note*=original]',f'{v}+ba',b])

def valid_link(text):
    matches=re.findall(r'https?://[^\s<>\[\]()]+',text)
    for item in matches:
        if urllib.parse.urlparse(item).hostname in ('youtube.com','www.youtube.com','m.youtube.com','music.youtube.com','youtu.be'):return item
    raise ValueError('Please enter a valid YouTube video link.')

def ffmpeg_path():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()

def deno_path():
    name='deno.exe' if sys.platform=='win32' else 'deno'
    for path in [RESOURCE/'tools'/name,Path(__file__).resolve().parents[1]/'Resources'/'tools'/name]:
        if path.is_file():return str(path)
    return shutil.which('deno')

@dataclass
class Request:
    source:str
    online:bool
    output:Path
    video:bool=True
    height:int=2160
    bitrate:int=192
    subtitle_language:str='en'
    audio_language:str|None='en'
    subtitles:bool=True
    subtitle_file:str=''
    start:float|None=None
    end:float|None=None

def subtitle_text(text,start=None,end=None):
    cues=[]
    for block in re.split(r'\n\s*\n',text.replace('\r\n','\n').strip()):
        lines=block.splitlines()
        timeindex=next((i for i,l in enumerate(lines) if '-->' in l),None)
        if timeindex is None:continue
        parts=lines[timeindex].split(' --> ')
        if len(parts)!=2:continue
        a,b=[parse_time(x.strip().replace(',','.')) for x in parts]
        if start is not None:
            if min(b,end)<=max(a,start):continue
            a,b=max(a,start)-start,min(b,end)-start
        def stamp(t):
            ms=round(t*1000)
            return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
        cues.append(f'{len(cues)+1}\n{stamp(a)} --> {stamp(b)}\n'+ '\n'.join(lines[timeindex+1:]))
    return '\n\n'.join(cues)+'\n'

def lrc(text):
    result=[]
    for block in re.split(r'\n\s*\n',text.strip()):
        lines=block.splitlines()
        if len(lines)<3 or '-->' not in lines[1]:continue
        a=parse_time(lines[1].split(' --> ')[0].replace(',','.'))
        clean=re.sub('<[^>]+>','',' '.join(lines[2:]))
        cs=round(a*100);result.append(f'[{cs//6000:02}:{cs//100%60:02}.{cs%100:02}]'+clean)
    return '\n'.join(result)+'\n'

class Engine:
    def __init__(self,emit=lambda kind,value:None):
        self.emit=emit;self.cancelled=threading.Event();self.process=None
    def cancel(self):
        self.cancelled.set()
        if self.process and self.process.poll() is None:self.process.terminate()
    def check(self):
        if self.cancelled.is_set():raise Cancelled('Cancelled.')
    def run(self,args):
        self.check()
        options={'creationflags':subprocess.CREATE_NO_WINDOW} if sys.platform=='win32' else {}
        # A temporary stderr file prevents a full pipe from blocking cancellation.
        with tempfile.TemporaryFile() as errors:
            p=subprocess.Popen([ffmpeg_path(),'-nostdin','-hide_banner','-loglevel','error','-y']+list(map(str,args)),stdout=subprocess.DEVNULL,stderr=errors,**options)
            self.process=p
            try:
                while True:
                    try:status=p.wait(timeout=.1);break
                    except subprocess.TimeoutExpired:self.check()
                self.check()
                if status:
                    errors.seek(0);raise RuntimeError(errors.read().decode(errors='replace')[-1500:])
            finally:
                if p.poll() is None:p.terminate();p.wait()
                self.process=None
    def hook(self,data):
        self.check()
        if data.get('status')=='downloading':
            total=data.get('total_bytes') or data.get('total_bytes_estimate')
            if total:self.emit('progress',min(100,data.get('downloaded_bytes',0)*100/total))
        elif data.get('status')=='finished':self.emit('status','Preparing…')
    def options(self):
        class Log:
            def debug(self,message):pass
            def warning(self,message):pass
            def error(self,message):pass
        values=dict(noplaylist=True,quiet=True,no_warnings=True,logger=Log(),socket_timeout=20,retries=2,fragment_retries=2,ffmpeg_location=ffmpeg_path(),progress_hooks=[self.hook])
        if deno_path():values['js_runtimes']={'deno':{'path':deno_path()}}
        return values
    def inspect(self,source,online):
        self.check()
        if online:
            import yt_dlp
            with yt_dlp.YoutubeDL(self.options()) as y:info=y.extract_info(valid_link(source),download=False)
            formats=info.get('formats',[])
            result={'title':info.get('title','MediaKeep'),'url':info.get('webpage_url',source),'height':max([x.get('height') or 0 for x in formats],default=0),'thumbnail':info.get('thumbnail'),'audio_languages':sorted(set(x['language'] for x in formats if x.get('language') and x.get('acodec')!='none'))}
            if result['thumbnail']:
                try:
                    url=urllib.parse.urlparse(result['thumbnail'])
                    if url.scheme=='https':
                        with urllib.request.urlopen(result['thumbnail'],timeout=10) as r:result['image']=r.read(8*1024*1024)
                except Exception:pass
        else:
            p=Path(source)
            if not p.is_file():raise ValueError('Choose a video file first.')
            result={'title':p.stem,'url':str(p)}
        self.check();return result
    def save(self,request:Request):
        r=request;self.check();r.output.parent.mkdir(parents=True,exist_ok=True)
        if not r.online and r.output.resolve()==Path(r.source).resolve():raise ValueError('Use a different name to protect the original file.')
        # Stage everything on the destination filesystem; partial files never appear as completed output.
        with tempfile.TemporaryDirectory(prefix='.mediakeep-',dir=str(r.output.parent)) as tmp:
            folder=Path(tmp);media=Path(r.source);sub=Path(r.subtitle_file) if r.subtitle_file else None;caption_warning=''
            if r.online:
                import yt_dlp
                options=self.options();options.update(outtmpl=str(folder/'media.%(ext)s'),format=video_format(r.height,r.audio_language) if r.video else audio_format(r.audio_language),merge_output_format='mp4')
                if r.subtitles and not sub:
                    aliases=language(r.subtitle_language)['subtitleAliases']
                    options.update(writesubtitles=True,writeautomaticsub=True,subtitleslangs=aliases+[c+'-orig' for c in aliases],subtitlesformat='vtt/best',ignoreerrors=False)
                self.emit('status','Downloading video and audio…' if r.video else 'Downloading audio from YouTube…')
                # Subtitle failure must not discard a successfully downloadable video.
                try:
                    with yt_dlp.YoutubeDL(options) as y:y.download([valid_link(r.source)])
                except Exception:
                    self.check()
                    if not r.subtitles or sub:raise
                    options.update(writesubtitles=False,writeautomaticsub=False)
                    self.emit('status','MP4 saved · Could not fetch subtitles.' if r.video else ' · Could not fetch subtitles; MP3 saved.')
                    with yt_dlp.YoutubeDL(options) as y:y.download([valid_link(r.source)])
                    caption_warning='MP4 saved · Could not fetch subtitles.' if r.video else ' · Could not fetch subtitles; MP3 saved.'
                movies=[p for p in folder.iterdir() if p.suffix in ['.mp4','.webm','.mkv','.m4a','.mp3','.opus','.ogg','.flac','.wav'] and p.name.startswith('media.')]
                if not movies:raise RuntimeError('Downloaded audio was not found.')
                media=sorted(movies,key=lambda p:p.stat().st_size,reverse=True)[0]
                if r.subtitles and not sub:
                    tracks=[p for p in folder.iterdir() if p.suffix in ['.vtt','.srt','.ass','.ssa']]
                    aliases=language(r.subtitle_language)['subtitleAliases']
                    def rank(p):return next((i for i,c in enumerate(aliases) if p.name.endswith('.'+c+p.suffix)),len(aliases))
                    sub=min(tracks,key=rank) if tracks else None
            staged=folder/('result.mp4' if r.video else 'result.mp3')
            seek=['-ss',str(r.start)] if r.start is not None else []
            limit=['-t',str(r.end-r.start)] if r.start is not None else []
            self.emit('status','Converting the selected range to MP4…' if r.video and seek else 'Preparing…' if r.video else 'Converting to MP3…')
            if r.video:
                codec=['-c:v','libx264','-preset','veryfast','-c:a','aac'] if seek else ['-c','copy']
                self.run(seek+['-i',media]+limit+['-map','0:v:0','-map','0:a:0?']+codec+['-movflags','+faststart',staged])
            else:self.run(seek+['-i',media]+limit+['-map','0:a:0','-vn','-c:a','libmp3lame','-b:a',f'{r.bitrate}k',staged])
            installs=[(staged,r.output)]
            if r.subtitles:
                if sub and sub.is_file():
                    try:
                        srt=folder/'result.srt';self.run(['-i',sub,'-map','0:s:0','-c:s','srt',srt])
                        text=subtitle_text(srt.read_text(encoding='utf-8-sig'),r.start,r.end)
                        if '-->' not in text:raise ValueError('No subtitles')
                        srt.write_text(text,encoding='utf-8');installs.append((srt,r.output.with_suffix('.srt')))
                        if r.video:
                            mux=folder/'subtitled.mp4'
                            try:
                                self.run(['-i',staged,'-i',srt,'-map','0:v:0','-map','0:a:0?','-map','1:s:0','-c','copy','-c:s','mov_text','-metadata:s:s:0','language='+language(r.subtitle_language)['iso639'],'-disposition:s:0','0',mux]);installs[0]=(mux,r.output)
                            except Cancelled:raise
                            except Exception:caption_warning='MP4 saved · Subtitles saved separately as SRT.'
                        else:
                            lyrics=folder/'result.lrc';lyrics.write_text(lrc(text),encoding='utf-8');installs.append((lyrics,r.output.with_suffix('.lrc')))
                    except Cancelled:raise
                    except Exception:caption_warning='MP4 saved · Could not save subtitles.' if r.video else ' · Could not convert subtitles; MP3 saved.'
                else:caption_warning='MP4 saved · No subtitles for the selected language.' if r.video else ' · No matching subtitles; MP3 saved.'
            self.check()
            protected=[Path(r.source).resolve()] if not r.online else []
            if r.subtitle_file:protected.append(Path(r.subtitle_file).resolve())
            if any(out.resolve() in protected for _,out in installs):raise ValueError('Use a different name to protect the original file.')
            # Keep copies of replaced files, then roll back if a later install fails.
            backups=[];written=[]
            try:
                for i,(src,out) in enumerate(installs):
                    backup=folder/f'backup-{i}'
                    if out.exists():shutil.copy2(out,backup);backups.append((backup,out))
                    os.replace(src,out);written.append(out)
            except Exception:
                for out in written:out.unlink(missing_ok=True)
                for backup,out in backups:os.replace(backup,out)
                raise
            return {'path':str(r.output),'warning':caption_warning,'subtitles':len(installs)>1}

def version(text):
    if not re.fullmatch(r'v?\d+\.\d+\.\d+(?:\.\d+)?',text):raise ValueError('Invalid release version')
    return tuple(map(int,text.lstrip('v').split('.')))+(0,)*(4-len(text.lstrip('v').split('.')))

def release_update(platform_name=None):
    import platform
    platform_name=platform_name or ('Windows' if sys.platform=='win32' else 'Linux')
    suffix={'Windows':'-Windows-x64.zip','Linux':'-Linux-x86_64.tar.gz'}[platform_name]
    request=urllib.request.Request(f'https://api.github.com/repos/{REPOSITORY}/releases/latest',headers={'User-Agent':'MediaKeep','Accept':'application/vnd.github+json'})
    with urllib.request.urlopen(request,timeout=20) as response:info=json.load(response)
    if info.get('draft') or info.get('prerelease') or version(info['tag_name'])<=version(VERSION):return None
    for asset in info.get('assets',[]):
        url=asset.get('browser_download_url','')
        if asset.get('state')=='uploaded' and asset.get('size',0)>0 and asset['name'].startswith('MediaKeep-') and asset['name'].endswith(suffix) and url.startswith(f'https://github.com/{REPOSITORY}/releases/download/'):
            return dict(version=info['tag_name'],notes=info.get('body',''),url=url)
    raise ValueError('The new release is not ready for this Mac yet.')
