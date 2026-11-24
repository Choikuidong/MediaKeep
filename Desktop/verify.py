import os,json,tempfile,sys,time
from pathlib import Path
from PySide6.QtCore import Qt,QUrl
from PySide6.QtGui import QPixmap,QFont,QRawFont
from core import *

def run(app):
    from mediakeep import Window
    if getattr(sys,'frozen',False):assert deno_path() and os.access(deno_path(),os.X_OK)
    fonts=[QRawFont(str(RESOURCE/'fonts'/name),14) for name in ['NotoSans.ttf','NotoSansCJK-Regular.otf']]
    assert all(f.isValid() for f in fonts),'Bundled fonts could not be loaded'
    for code,strings in STRINGS.items():
        for ch in set(''.join(strings.values())):
            if ch.isalnum():assert any(f.supportsCharacter(ord(ch)) for f in fonts),(code,ch,'Missing glyph')
    assert len(LANGUAGES)==20 and len(set(x['code'] for x in LANGUAGES))==20
    keys=set(STRINGS['ja'])
    for code in STRINGS:
        if code not in ['en','ko']:assert set(STRINGS[code])==keys,code
    assert version('v1.0.1')>version('1.0.0')
    assert clean_name('CON')=='_CON' and clean_name('../a:b')=='a b'
    for bad in ['https://evil.test/?url=https://youtube.com','https://youtube.com.evil.test/watch?v=1']:
        try:valid_link(bad)
        except ValueError:pass
        else:raise AssertionError('Unsafe URL accepted')
    assert parse_time('1:02:03.5')==3723.5
    try:parse_time('1:70')
    except ValueError:pass
    else:raise AssertionError('Invalid timestamp accepted')
    text='1\n00:00:01,000 --> 00:00:03,000\nHello <b>MediaKeep</b>\n'
    shifted=subtitle_text(text,2,2.75)
    assert '00:00:00,000 --> 00:00:00,750' in shifted and '[00:00.00]Hello MediaKeep' in lrc(shifted)
    assert 'language^=ja' in audio_format('ja') and 'height<=2160' in video_format(2160,'es')
    window=Window(testing=True)
    window.destination=Path.home()/'Downloads'
    window.folders=[{'path':str(window.destination),'name':'Downloads'},{'path':str(Path.home()/'Videos'),'name':'Videos'},{'path':str(Path.home()/'Music'),'name':'Music'}]
    window.refresh_folders()
    # Exercise each translation and both tabs; capture real widget rendering for README.
    screenshot=Path(os.environ.get('MEDIAKEEP_SCREENSHOTS',tempfile.gettempdir()));screenshot.mkdir(parents=True,exist_ok=True)
    for code in [l['code'] for l in LANGUAGES]:
        window.lang=code;window.translate()
        assert window.language.currentData()==code and window.sub_language.count()==21 and window.audio_choice.count()==22
        for video in [True,False]:window.change_tab(video);window.show();app.processEvents();assert len(window.folder_buttons)==9
    window.lang='en';window.translate()
    for theme in range(4):
        window.theme=theme;window.apply_theme();window.change_tab(True);app.processEvents()
        window.grab().save(str(screenshot/f'desktop-theme-{theme}.png'))
    # Real local conversion via packaged FFmpeg, including trimmed subtitles and MP4 embedding.
    engine=Engine()
    with tempfile.TemporaryDirectory() as name:
        root=Path(name);movie=root/'input.mp4';sub=root/'input.srt';sub.write_text(text,encoding='utf-8')
        engine.run(['-f','lavfi','-i','color=c=blue:s=320x180:d=4','-f','lavfi','-i','sine=frequency=440:duration=4','-c:v','libx264','-c:a','aac','-shortest',movie])
        window.filename.clear()
        window.inspected({'title':'First','url':str(movie)},str(movie),False)
        window.inspected({'title':'Second','url':str(movie)},str(movie),False)
        assert window.filename.text()=='Second'
        window.filename.setText('Custom')
        window.inspected({'title':'Third','url':str(movie)},str(movie),False)
        assert window.filename.text()=='Custom'
        out=root/'音楽 test.mp3';result=engine.save(Request(str(movie),False,out,False,subtitle_file=str(sub),start=2,end=2.75))
        assert out.stat().st_size>100 and '[00:00.00]' in out.with_suffix('.lrc').read_text(encoding='utf-8')
        video=root/'video.mp4';result=engine.save(Request(str(movie),False,video,True,subtitle_file=str(sub),subtitle_language='ja',start=1,end=3))
        assert video.stat().st_size>100 and video.with_suffix('.srt').is_file()
        # Cancelled jobs must never create a completed output.
        cancelled=Engine();cancelled.cancel()
        try:cancelled.save(Request(str(movie),False,root/'cancelled.mp3',False))
        except Cancelled:pass
        else:raise AssertionError('Cancellation failed')
        assert not (root/'cancelled.mp3').exists()
        window.show_media(video);app.processEvents();assert window.player.source()==QUrl.fromLocalFile(str(video))
        from PySide6.QtMultimedia import QMediaPlayer
        deadline=time.time()+15
        while window.player.mediaStatus() not in [QMediaPlayer.LoadedMedia,QMediaPlayer.BufferedMedia,QMediaPlayer.InvalidMedia] and time.time()<deadline:
            app.processEvents();time.sleep(.02)
        assert window.player.mediaStatus()!=QMediaPlayer.InvalidMedia,window.player.errorString()
        assert window.player.mediaStatus() in [QMediaPlayer.LoadedMedia,QMediaPlayer.BufferedMedia],window.player.mediaStatus()
        window.player.stop();window.player.setSource(QUrl())
        # Follow the same asynchronous Inspect -> Save chain used by the Download button.
        window.change_tab(False);window.mode.setCurrentIndex(0);window.source_file=str(movie);window.caption_file=str(sub);window.destination=root;window.filename.setText('UI-converted');window.entire.setChecked(True);window.inspect(True)
        deadline=time.time()+35
        while (window.work or window.pending_save or not (root/'UI-converted.mp3').exists()) and time.time()<deadline:
            app.processEvents();time.sleep(.02)
        assert (root/'UI-converted.mp3').exists() and window.last_output==root/'UI-converted.mp3',window.status.text()
        assert not window.work and window.reveal.isEnabled()
        window.player.stop();window.player.setSource(QUrl())
    window.close();app.processEvents()
    print('PASS: 20 languages; both tabs; four themes; file names; URLs; versions; FFmpeg MP3/SRT/LRC and MP4; cancellation; Qt media source',flush=True)
    return 0
