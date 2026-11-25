"""MediaKeep desktop UI for Windows and Linux."""
from __future__ import annotations
import sys, os, json, time, platform
from pathlib import Path
from PySide6.QtCore import Qt,QThread,Signal,QObject,QUrl,QSettings,QMimeData,QTimer
from PySide6.QtGui import QIcon,QPixmap,QDrag,QDesktopServices,QAction,QFont,QFontDatabase,QPainter
from PySide6.QtWidgets import (QApplication,QMainWindow,QWidget,QVBoxLayout,QHBoxLayout,QGridLayout,QLabel,QPushButton,QComboBox,QLineEdit,QCheckBox,QButtonGroup,QGroupBox,QProgressBar,QFileDialog,QMessageBox,QDialog,QDialogButtonBox,QInputDialog,QSlider)
from PySide6.QtMultimedia import QMediaPlayer,QAudioOutput
from PySide6.QtMultimediaWidgets import QVideoWidget
from core import VERSION,RESOURCE,LANGUAGES,Engine,Request,Cancelled,tr,parse_time,clean_name,valid_link,release_update,language

THEMES = [
    ('Midnight Blue','#101c30','#1b2b42','#f4f7ff','#b8c5d9','#299fff','#35465d'),
    ('Warm Amber','#221e1b','#302a25','#fff8ed','#cbbfb0','#ffbb37','#51463b'),
    ('Soft Light','#f3f4f8','#ffffff','#192033','#566176','#4338ca','#dce0e9'),
    ('Forest Green','#10251e','#1e352c','#f3fff8','#b8cdbf','#84eba3','#385647'),
    ('Lavender Night','#1b1726','#282234','#eae1f6','#bdb0ce','#c9a8ff','#4a3e59'),
    ('Ocean Teal','#101f24','#172b30','#e4f1ef','#b4cbca','#68ded0','#315158'),
    ('Peach Cream','#f7eee8','#fff9f5','#322521','#715a50','#a33d32','#e1cfc4'),
]

SETTINGS_KOREAN = {
    'Interface language': '앱 언어',
    'Lavender Night': '라벤더 나이트',
    'Ocean Teal': '오션 틸',
    'Peach Cream': '피치 크림',
    'Changes apply immediately across the app.': '선택하면 앱 화면에 바로 적용됩니다.',
    'Support MediaKeep': 'MediaKeep 개발을 응원해 주세요',
    'If MediaKeep saves you time, you can help fund future updates.': '도움이 되셨다면 다음 업데이트를 응원해 주세요.',
    'MediaKeep is free to use, with or without sponsorship.': '후원은 선택이며, 앱은 누구나 무료로 이용하실 수 있습니다.',
    'Support on GitHub ↗': 'GitHub에서 후원하기 ↗',
}
SPONSORS_URL = 'https://github.com/sponsors/Choikuidong'


class Worker(QObject):
    event=Signal(str,object);done=Signal(object);error=Signal(str);finished=Signal()
    def __init__(self,kind,payload):
        super().__init__();self.kind=kind;self.payload=payload;self.engine=Engine(lambda k,v:self.event.emit(k,v))
    def run(self):
        try:
            value=release_update() if self.kind=='update' else self.engine.inspect(*self.payload) if self.kind=='inspect' else self.engine.save(self.payload)
            self.done.emit(value)
        except Cancelled:self.error.emit('Cancelled.')
        except Exception as error:self.error.emit(str(error))
        finally:self.finished.emit()

class FolderButton(QPushButton):
    moved=Signal(int,int)
    def __init__(self,index,parent=None):super().__init__(parent);self.index=index;self.setAcceptDrops(True);self.origin=None;self.filled=False
    def paintEvent(self,event):
        super().paintEvent(event)
        if self.filled:
            painter=QPainter(self);painter.setRenderHint(QPainter.Antialiasing);painter.setPen(Qt.NoPen);painter.setBrush(self.palette().buttonText())
            for x in [7,11]:
                for y in [-5,0,5]:painter.drawEllipse(x,self.height()//2+y,2,2)
    def mousePressEvent(self,event):self.origin=event.position().toPoint();super().mousePressEvent(event)
    def mouseMoveEvent(self,event):
        if self.origin is not None and event.buttons()&Qt.LeftButton and (event.position().toPoint()-self.origin).manhattanLength()>QApplication.startDragDistance():
            drag=QDrag(self);mime=QMimeData();mime.setData('application/x-mediakeep-folder',str(self.index).encode());drag.setMimeData(mime);drag.setPixmap(self.grab());self.setDown(False);drag.exec(Qt.MoveAction);self.origin=None
    def dragEnterEvent(self,event):
        if self.isEnabled() and event.mimeData().hasFormat('application/x-mediakeep-folder'):event.acceptProposedAction()
    def dropEvent(self,event):
        try:self.moved.emit(int(bytes(event.mimeData().data('application/x-mediakeep-folder'))),self.index);event.acceptProposedAction()
        except ValueError:pass

class Window(QMainWindow):
    def __init__(self,testing=False):
        super().__init__();self.testing=testing;self.settings=QSettings('AppleCraft','MediaKeep')
        self.lang=self.settings.value('language','en');self.theme=self.settings.value('theme',2,type=int)
        self.theme=self.theme if 0<=self.theme<len(THEMES) else 2;self.bindings=[];self.work=None;self.thread=None;self.update_thread=None;self.update_worker=None;self.closing=False
        self.destination=Path(self.settings.value('destination',str(Path.home()/'Downloads')))
        self.folders=json.loads(self.settings.value('folders','[]'))[:9]
        if not self.folders:self.folders=[{'path':str(self.destination),'name':''}]
        self.source_file='';self.caption_file='';self.auto_name='';self.last_output=None;self.info=None;self.pending_save=False;self.preview_url=''
        self.setWindowTitle('MediaKeep '+VERSION);self.setWindowIcon(QIcon(str(RESOURCE/'MediaKeep.png')));self.resize(1120,820);self.setMinimumSize(1060,780)
        self.player=QMediaPlayer(self);self.audio=QAudioOutput(self);self.audio.setVolume(.65);self.player.setAudioOutput(self.audio)
        self.build();self.translate();self.apply_theme();self.refresh_folders()
        if not testing:
            QTimer.singleShot(3000,lambda:self.check_update(False));self.update_timer=QTimer(self);self.update_timer.timeout.connect(lambda:self.check_update(False));self.update_timer.start(3600000)
    def t(self,key):return tr(key,self.lang)
    def text(self,widget,key,kind='text'):
        self.bindings.append((widget,key,kind));return widget
    def label(self,key):return self.text(QLabel(),key)
    def button(self,key,callback):
        b=self.text(QPushButton(),key);b.clicked.connect(callback);b.setMinimumHeight(29);return b
    def group(self,key):
        w=self.text(QGroupBox(),key,'title');layout=QVBoxLayout(w);layout.setContentsMargins(16,23,16,12);layout.setSpacing(8);return w,layout
    def combo(self,items):
        box=QComboBox()
        for label,value in items:box.addItem(label,value)
        return box
    def row(self,*widgets):
        layout=QHBoxLayout();layout.setSpacing(8)
        for w in widgets:layout.addWidget(w)
        return layout
    def build(self):
        central=QWidget();self.setCentralWidget(central);root=QVBoxLayout(central);root.setContentsMargins(20,15,20,12);root.setSpacing(12)
        icon=QLabel();icon.setPixmap(QPixmap(str(RESOURCE/'MediaKeep.png')).scaled(44,44,Qt.KeepAspectRatio,Qt.SmoothTransformation));brand=QLabel('MediaKeep');brand.setObjectName('brand')
        top=self.row(icon,brand);top.addStretch();self.settings_button=self.button('Settings…',self.show_settings);top.addWidget(self.settings_button);root.addLayout(top)
        tabs=QHBoxLayout();tabs.addStretch();self.video_tab=self.button('Video Download',lambda:self.change_tab(True));self.audio_tab=self.button('Audio Extraction',lambda:self.change_tab(False))
        self.nav=QButtonGroup(self);self.nav.setExclusive(True)
        for b in (self.video_tab,self.audio_tab):b.setCheckable(True);b.setMinimumWidth(220);self.nav.addButton(b);tabs.addWidget(b)
        self.video_tab.setChecked(True);tabs.addStretch();root.addLayout(tabs)
        columns=QHBoxLayout();columns.setSpacing(16);left=QVBoxLayout();right=QVBoxLayout();left.setSpacing(10);right.setSpacing(10);columns.addLayout(left,1);columns.addLayout(right,1);root.addLayout(columns,1)
        source,sl=self.group('01  Video source');left.addWidget(source)
        self.mode=self.combo([('Local video','local'),('YouTube link','online')]);self.mode.currentIndexChanged.connect(self.source_mode);sl.addWidget(self.mode)
        self.link=self.text(QLineEdit(),'Paste a YouTube video link','placeholder');sl.addWidget(self.link)
        self.local_row=QWidget();lr=QHBoxLayout(self.local_row);lr.setContentsMargins(0,0,0,0);self.choose_video=self.button('Choose video…',self.pick_video);lr.addWidget(self.choose_video);self.local_name=self.label('No video selected');self.local_name.setWordWrap(True);lr.addWidget(self.local_name,1);sl.addWidget(self.local_row)
        settings,ss=self.group('02  Video settings');self.settings_group=settings;left.addWidget(settings)
        self.quality=self.combo([('4K · 2160p',2160),('Full HD · 1080p',1080),('HD · 720p',720),('SD · 480p',480)])
        self.bitrate=self.combo([('320 kbps · ~2.4 MB/min',320),('192 kbps · ~1.4 MB/min',192),('128 kbps · ~1.0 MB/min',128)]);self.bitrate.setCurrentIndex(1)
        self.quality_label=self.label('Quality');ss.addLayout(self.row(self.quality_label,self.quality,self.bitrate))
        self.subs=self.text(QCheckBox(),'Save subtitles');self.subs.setChecked(True);self.sub_language=self.combo([('App language','app')]+[(l['name'],l['code']) for l in LANGUAGES]);ss.addLayout(self.row(self.subs,self.sub_language))
        self.audio_choice=self.combo([('App language · Prefer dub','app'),('Original audio','original')]+[(l['name'],l['code']) for l in LANGUAGES]);ss.addLayout(self.row(self.label('Audio track'),self.audio_choice))
        self.dub_hint=self.label('Matching dub preferred; original audio used if unavailable.');self.dub_hint.setWordWrap(True);self.dub_hint.setObjectName('hint');ss.addWidget(self.dub_hint)
        self.caption_row=QWidget();cl=QHBoxLayout(self.caption_row);cl.setContentsMargins(0,0,0,0);cl.addWidget(self.button('Choose subtitles…',self.pick_subtitle));cl.addWidget(self.button('Clear',self.clear_subtitle));self.caption_label=QLabel();self.caption_label.setMaximumWidth(180);cl.addWidget(self.caption_label);ss.addWidget(self.caption_row)
        range_group,rl=self.group('Save range');left.addWidget(range_group)
        self.entire=self.text(QCheckBox(),'Entire video');self.entire.setChecked(True);self.entire.toggled.connect(self.range_changed);self.start=self.text(QLineEdit(),'Start 00:00','placeholder');self.end=self.text(QLineEdit(),'End 00:00','placeholder');self.start.setMaximumWidth(118);self.end.setMaximumWidth(118);rl.addLayout(self.row(self.entire,self.start,self.end));self.range_hint=self.label('Without a range, the entire video is saved.');self.range_hint.setWordWrap(True);self.range_hint.setObjectName('hint');rl.addWidget(self.range_hint)
        folder,fl=self.group('03  Save location');left.addWidget(folder,1);self.folder_path=QLabel();self.folder_path.setWordWrap(True);self.folder_path.setObjectName('hint');fl.addLayout(self.row(self.folder_path,self.button('Choose folder…',lambda:self.choose_folder(False))))
        grid=QGridLayout();self.folder_buttons=[]
        for i in range(9):
            b=FolderButton(i);b.setMinimumHeight(30);b.setCheckable(True);b.clicked.connect(lambda checked=False,i=i:self.select_folder(i));b.moved.connect(self.move_folder);grid.addWidget(b,i//3,i%3);self.folder_buttons.append(b)
        fl.addLayout(grid);fl.addWidget(self.button('Edit names',self.edit_names));hint=self.label('Drag to reorder · Up to 9 locations');hint.setWordWrap(True);hint.setObjectName('hint');fl.addWidget(hint)
        preview,pl=self.group('Preview');right.addWidget(preview,1);self.inspect_button=self.button('Load preview',lambda:self.inspect(False));pl.addWidget(self.inspect_button)
        self.video_widget=QVideoWidget();self.video_widget.setMinimumHeight(230);self.player.setVideoOutput(self.video_widget);self.video_widget.hide();pl.addWidget(self.video_widget)
        self.thumbnail=QLabel();self.thumbnail.setMinimumSize(430,230);self.thumbnail.setAlignment(Qt.AlignCenter);self.thumbnail.setObjectName('thumbnail');pl.addWidget(self.thumbnail,1)
        self.play=self.button('▶',self.play_pause);self.seek=QSlider(Qt.Horizontal);self.seek.sliderMoved.connect(self.player.setPosition);self.player.positionChanged.connect(self.seek.setValue);self.player.durationChanged.connect(lambda v:self.seek.setRange(0,v));pl.addLayout(self.row(self.play,self.seek))
        self.preview_note=self.label('Your video preview will appear here.');self.preview_note.setWordWrap(True);self.preview_note.setObjectName('hint');pl.addWidget(self.preview_note);pl.addWidget(self.button('▷ Preview original',self.preview_original))
        save,sav=self.group('Save file');right.addWidget(save);self.filename=self.text(QLineEdit(),'Automatically use the video title','placeholder');sav.addWidget(self.filename);self.status=self.label('Paste a YouTube link to download.');self.status.setWordWrap(True);self.status.setMinimumHeight(35);sav.addWidget(self.status)
        self.progress=QProgressBar();self.progress.setRange(0,100);self.progress.setValue(0);sav.addWidget(self.progress)
        self.save_button=self.button('Download MP4',lambda:self.inspect(True));self.save_button.setObjectName('primary');self.save_button.setMinimumHeight(39);self.cancel=self.button('Cancel',self.cancel_work);self.cancel.hide();sav.addLayout(self.row(self.save_button,self.cancel));self.reveal=self.button('Reveal saved file',self.reveal_file);self.reveal.setEnabled(False);sav.addWidget(self.reveal)
        notice=self.label('Please download only content you have permission to use. You are responsible for your use.');notice.setWordWrap(True);notice.setObjectName('hint');root.addWidget(notice)
        self.range_changed();self.source_mode();self.change_tab(True)
        menu=self.menuBar().addMenu('MediaKeep');self.settings_action=QAction(self);self.settings_action.triggered.connect(self.show_settings);menu.addAction(self.settings_action);self.update_action=QAction(self);self.update_action.triggered.connect(lambda:self.check_update(True));menu.addAction(self.update_action);self.about_action=QAction(self);self.about_action.triggered.connect(self.about);menu.addAction(self.about_action)
    def translate(self):
        for widget,key,kind in self.bindings:
            text=self.t(key)
            if kind=='placeholder':widget.setPlaceholderText(text)
            elif kind=='title':widget.setTitle(text)
            else:widget.setText(text)
            widget.setToolTip(text)
        self.mode.setItemText(0,self.t('Local video'));self.mode.setItemText(1,self.t('YouTube link'));self.sub_language.setItemText(0,self.t('App language'));self.audio_choice.setItemText(0,self.t('App language · Prefer dub'));self.audio_choice.setItemText(1,self.t('Original audio'))
        self.settings_action.setText(self.t('Settings…'));self.update_action.setText(self.t('Check for Updates…'));self.about_action.setText(self.t('About MediaKeep'))
        self.change_tab(self.video_tab.isChecked());self.refresh_folders()
    def change_language(self, code):
        if not code or self.lang == code:
            return
        self.lang = code
        self.settings.setValue('language', code)
        self.translate()
    def change_tab(self,video):
        self.video_tab.setChecked(video);self.audio_tab.setChecked(not video);self.mode.setVisible(not video);self.quality.setVisible(video);self.bitrate.setVisible(not video);self.caption_row.setVisible(not video)
        self.settings_group.setTitle(self.t('02  Video settings' if video else '02  Audio settings'));self.quality_label.setText(self.t('Quality' if video else 'MP3 quality'));self.save_button.setText(self.t('Download MP4' if video else 'Extract MP3'));self.source_mode()
    def source_mode(self):
        online=self.video_tab.isChecked() or self.mode.currentData()=='online';self.link.setVisible(online);self.local_row.setVisible(not online);self.info=None
    def range_changed(self):self.start.setEnabled(not self.entire.isChecked());self.end.setEnabled(not self.entire.isChecked())
    def pick_video(self):
        name,_=QFileDialog.getOpenFileName(self,self.t('Choose video…'),str(Path.home()),'Video (*.mp4 *.mkv *.mov *.webm *.avi *.m4v);;All files (*)')
        if name:self.source_file=name;self.local_name.setText(Path(name).name);self.info=None
    def pick_subtitle(self):
        name,_=QFileDialog.getOpenFileName(self,self.t('Choose subtitles…'),'','Subtitles (*.srt *.vtt *.ass *.ssa)')
        if name:self.caption_file=name;self.caption_label.setText(Path(name).name);self.caption_label.setToolTip(name);self.subs.setChecked(True)
    def clear_subtitle(self):self.caption_file='';self.caption_label.clear()
    def folder_dialog(self):
        dialog=QFileDialog(self,self.t('Choose folder…'),str(self.destination));dialog.setFileMode(QFileDialog.Directory);dialog.setOption(QFileDialog.ShowDirsOnly,True)
        # Qt's native Windows/Finder dialog and the Qt Linux picker both support folder creation.
        if dialog.exec():return Path(dialog.selectedFiles()[0])
    def choose_folder(self,add):
        if self.work:return
        path=self.folder_dialog()
        if path:
            self.destination=path
            if add and len(self.folders)<9:self.folders.append({'path':str(path),'name':''})
            self.refresh_folders()
    def refresh_folders(self):
        self.folder_path.setText(str(self.destination));self.folder_path.setToolTip(str(self.destination))
        for i,b in enumerate(self.folder_buttons):
            if i<len(self.folders):
                item=self.folders[i];b.filled=True;b.setText(item['name'] or Path(item['path']).name);b.setToolTip(item['path']);b.setChecked(Path(item['path'])==self.destination)
            else:b.filled=False;b.setText(self.t('+ Add location'));b.setChecked(False)
        if not self.testing:self.settings.setValue('folders',json.dumps(self.folders,ensure_ascii=False));self.settings.setValue('destination',str(self.destination))
    def select_folder(self,i):
        if self.work:return
        if i<len(self.folders):self.destination=Path(self.folders[i]['path']);self.refresh_folders()
        else:self.choose_folder(True)
    def move_folder(self,a,b):
        if self.work or not 0<=a<len(self.folders) or not 0<=b<9:return
        item=self.folders.pop(a);self.folders.insert(min(b,len(self.folders)),item);self.refresh_folders()
    def edit_names(self):
        if not self.folders:return
        choices=[v['name'] or Path(v['path']).name for v in self.folders];name,ok=QInputDialog.getItem(self,self.t('Edit names'),self.t('03  Save location'),choices,0,False)
        if not ok:return
        i=choices.index(name);box=QMessageBox(self);box.setWindowTitle(self.t('Edit names'));box.setText(self.t('Leave the name empty to use the folder name.'));edit=box.addButton(self.t('Save name'),QMessageBox.AcceptRole);remove=box.addButton(self.t('Remove shortcut'),QMessageBox.DestructiveRole);box.addButton(self.t('Cancel'),QMessageBox.RejectRole);box.exec()
        if box.clickedButton()==remove:self.folders.pop(i)
        elif box.clickedButton()==edit:
            value,ok=QInputDialog.getText(self,self.t('Edit names'),self.t('New name'),text=self.folders[i]['name'])
            if ok:self.folders[i]['name']=value.strip()
        self.refresh_folders()
    def busy(self,value):
        for w in [self.settings_button,self.video_tab,self.audio_tab,self.mode,self.choose_video,self.link,self.filename,self.quality,self.bitrate,self.subs,self.sub_language,self.audio_choice,self.entire,self.save_button,self.inspect_button]+self.folder_buttons:w.setEnabled(not value)
        self.caption_row.setEnabled(not value);self.cancel.setVisible(value)
        if value:self.progress.setRange(0,0)
        else:self.progress.setRange(0,100);self.range_changed()
    def start_worker(self,kind,payload,callback):
        if self.work:return
        self.busy(True);thread=QThread(self);worker=Worker(kind,payload);worker.moveToThread(thread);self.work=worker;self.thread=thread;thread.started.connect(worker.run)
        worker.event.connect(self.task_event);worker.done.connect(callback);worker.error.connect(self.failed);worker.finished.connect(thread.quit);worker.finished.connect(worker.deleteLater);thread.finished.connect(self.worker_finished);thread.finished.connect(thread.deleteLater);thread.start()
    def worker_finished(self):
        self.work=None;self.thread=None;self.busy(False)
        if self.closing:self.close();return
        if self.pending_save:self.pending_save=False;QTimer.singleShot(0,self.start_save)
    def task_event(self,kind,value):
        if kind=='status':self.status.setText(self.t(value))
        elif kind=='progress':self.progress.setRange(0,100);self.progress.setValue(round(value));self.status.setText(f'{self.t("Video" if self.video_tab.isChecked() else "Audio")}  {value:.1f}%')
    def failed(self,message):self.pending_save=False;self.status.setText(self.t(message));self.progress.setRange(0,100)
    def cancel_work(self):
        self.pending_save=False
        if self.work:self.work.engine.cancel()
    def inspect(self,save):
        if self.work:return
        online=self.video_tab.isChecked() or self.mode.currentData()=='online'
        try:
            source=valid_link(self.link.text()) if online else self.source_file
            if not source:raise ValueError('Choose a video file first.')
        except ValueError as error:self.failed(str(error));return
        self.pending_save=save;self.status.setText(self.t('Fetching video information…'));self.start_worker('inspect',(source,online),lambda info:self.inspected(info,source,online))
    def inspected(self,info,source,online):
        self.info=dict(info,source=source,online=online);self.preview_url=info['url'];self.preview_note.setText(info['title'])
        if not self.filename.text().strip() or self.filename.text()==self.auto_name:self.filename.setText(clean_name(info['title']))
        self.auto_name=clean_name(info['title'])
        if info.get('image'):
            image=QPixmap();image.loadFromData(info['image']);self.thumbnail.setPixmap(image.scaled(500,270,Qt.KeepAspectRatio,Qt.SmoothTransformation));self.player.stop();self.video_widget.hide();self.thumbnail.show()
        elif not online:self.show_media(Path(source))
        self.status.setText(self.t('Preparing…'))
    def start_save(self):
        if not self.info:return
        try:
            video=self.video_tab.isChecked();suffix='.mp4' if video else '.mp3';name=clean_name(self.filename.text() or self.info['title'])
            if name.lower().endswith(suffix):name=name[:-len(suffix)]
            output=self.destination/(name+suffix)
            outputs=[output]+([output.with_suffix('.srt')]+([] if video else [output.with_suffix('.lrc')]) if self.subs.isChecked() else [])
            protected=[] if self.info['online'] else [Path(self.info['source']).resolve()]
            if self.caption_file and self.subs.isChecked():protected.append(Path(self.caption_file).resolve())
            if any(p.resolve() in protected for p in outputs):raise ValueError('Use a different name to protect the original file.')
            if any(p.exists() for p in outputs) and QMessageBox.question(self,'MediaKeep',self.t('Replace the existing file?'))!=QMessageBox.Yes:return
            start=end=None
            if not self.entire.isChecked():
                start=parse_time(self.start.text() or '0');end=parse_time(self.end.text())
                if end<=start:raise ValueError('Check the start and end times.')
            lang=self.sub_language.currentData();lang=self.lang if lang=='app' else lang
            a=self.audio_choice.currentData();a=language(self.lang if a=='app' else a)['audio'] if a!='original' else None
            r=Request(self.info['source'],self.info['online'],output,video,self.quality.currentData(),self.bitrate.currentData(),lang,a,self.subs.isChecked(),self.caption_file if not video else '',start,end)
            self.start_worker('save',r,self.saved)
        except Exception as error:self.failed(str(error))
    def saved(self,result):
        self.last_output=Path(result['path']);self.reveal.setEnabled(True);self.progress.setRange(0,100);self.progress.setValue(100);self.status.setText(self.t(result['warning']) if result['warning'] else self.t('Saved · ')+self.last_output.name);self.show_media(self.last_output)
    def show_media(self,path):
        self.thumbnail.hide();self.video_widget.show();self.player.setSource(QUrl.fromLocalFile(str(path)));self.preview_url=str(path)
    def play_pause(self):
        if self.player.playbackState()==QMediaPlayer.PlayingState:self.player.pause()
        else:self.player.play()
    def preview_original(self):
        if self.preview_url:QDesktopServices.openUrl(QUrl(self.preview_url) if self.preview_url.startswith('https://') else QUrl.fromLocalFile(self.preview_url))
    def reveal_file(self):
        if self.last_output:
            if sys.platform=='win32':
                import subprocess
                subprocess.Popen(['explorer.exe','/select,',str(self.last_output)])
            else:QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.last_output.parent)))
    def apply_theme(self):
        _,bg,card,text,muted,accent,border=THEMES[self.theme]
        ink='#ffffff' if self.theme in (2,6) else '#102030'
        self.setStyleSheet(f'''QMainWindow,QDialog{{background:{bg};color:{text}}} QWidget{{color:{text};font-size:12px}} QLabel#brand{{font-size:26px;font-weight:700;color:{accent}}} QGroupBox{{background:{card};border:1px solid {border};border-radius:12px;margin-top:9px;font-weight:600}} QGroupBox::title{{subcontrol-origin:margin;left:16px;padding:0 5px;color:{accent}}} QPushButton,QComboBox,QLineEdit{{background:{card};border:1px solid {border};border-radius:6px;padding:6px}} QPushButton:hover{{border-color:{accent}}} QPushButton:checked{{background:{accent};color:{ink}}} QPushButton#primary{{background:{accent};color:{ink};font-size:15px;font-weight:600}} QPushButton:disabled,QLineEdit:disabled{{color:{muted};background:{bg}}} QLabel#hint{{color:{muted};font-size:11px}} QLabel#supportTitle{{color:{accent};font-size:16px;font-weight:700}} QLabel#thumbnail{{background:#11161b;border-radius:7px}} QProgressBar{{border:1px solid {border};border-radius:4px;text-align:center;min-height:15px}} QProgressBar::chunk{{background:{accent};border-radius:3px}} QComboBox QAbstractItemView{{background:{card};color:{text};selection-background-color:{accent}}}''')
    def settings_dialog(self):
        dialog = QDialog(self)
        dialog.setMinimumWidth(510)
        layout = QVBoxLayout(dialog)
        layout.setContentsMargins(24, 21, 24, 21)

        language_label = QLabel()
        languages = self.combo([(item['name'], item['code']) for item in LANGUAGES])
        languages.setObjectName('settingsLanguage')
        languages.setCurrentIndex(max(0, languages.findData(self.lang)))
        language_label.setBuddy(languages)
        layout.addWidget(language_label)
        layout.addWidget(languages)
        language_hint = QLabel()
        language_hint.setObjectName('hint')
        layout.addWidget(language_hint)

        theme_label = QLabel()
        themes = self.combo([(name, i) for i, (name, *_) in enumerate(THEMES)])
        themes.setObjectName('settingsTheme')
        themes.setCurrentIndex(self.theme)
        theme_label.setBuddy(themes)
        layout.addWidget(theme_label)
        layout.addWidget(themes)
        layout.addSpacing(8)

        automatic = QCheckBox()
        automatic.setChecked(self.settings.value('automaticUpdates', True, type=bool))
        automatic.toggled.connect(lambda checked: self.settings.setValue('automaticUpdates', checked))
        layout.addWidget(automatic)
        update_hint = QLabel()
        update_hint.setWordWrap(True)
        update_hint.setObjectName('hint')
        layout.addWidget(update_hint)
        update = QPushButton()
        update.clicked.connect(lambda: self.check_update(True))
        layout.addWidget(update, alignment=Qt.AlignLeft)
        layout.addWidget(QLabel('GitHub · Choikuidong/MediaKeep'))
        layout.addSpacing(8)

        support = QGroupBox()
        support_layout = QHBoxLayout(support)
        copy = QVBoxLayout()
        support_layout.addLayout(copy, 1)
        heading = QLabel()
        heading.setObjectName('supportTitle')
        pitch = QLabel()
        free = QLabel()
        free.setObjectName('hint')
        for label in (heading, pitch, free):
            label.setWordWrap(True)
            copy.addWidget(label)
        sponsor = QPushButton()
        sponsor.setObjectName('primary')
        sponsor.clicked.connect(lambda: QDesktopServices.openUrl(QUrl(SPONSORS_URL)))
        copy.addWidget(sponsor, alignment=Qt.AlignLeft)
        copy.addStretch()
        kakao = QWidget()
        kakao.setObjectName('kakaoSupport')
        qr_layout = QVBoxLayout(kakao)
        qr_layout.setContentsMargins(0, 0, 0, 0)
        qr = QLabel()
        qr.setPixmap(QPixmap(str(RESOURCE/'KakaoPay.png')).scaled(122, 122, Qt.KeepAspectRatio, Qt.SmoothTransformation))
        qr.setAccessibleName('카카오페이 후원 QR 코드')
        qr_layout.addWidget(qr, alignment=Qt.AlignHCenter)
        qr_layout.addWidget(QLabel('카카오페이로 후원하기'), alignment=Qt.AlignHCenter)
        support_layout.addWidget(kakao, alignment=Qt.AlignTop)
        layout.addWidget(support)

        def localize():
            def setting_text(key):
                return SETTINGS_KOREAN.get(key, self.t(key)) if self.lang == 'ko' else self.t(key)

            dialog.setWindowTitle(setting_text('MediaKeep Settings'))
            for widget, key in (
                (language_label, 'Interface language'),
                (language_hint, 'Changes apply immediately across the app.'),
                (theme_label, 'Appearance'),
                (automatic, 'Automatically check for updates'),
                (update_hint, 'Checks on launch and daily while the app is running.'),
                (update, 'Check for Updates…'),
                (heading, 'Support MediaKeep'),
                (pitch, 'If MediaKeep saves you time, you can help fund future updates.'),
                (free, 'MediaKeep is free to use, with or without sponsorship.'),
                (sponsor, 'Support on GitHub ↗'),
            ):
                widget.setText(setting_text(key))
            for i, (name, *_) in enumerate(THEMES):
                themes.setItemText(i, setting_text(name))
            kakao.setVisible(self.lang == 'ko')
            dialog.adjustSize()

        def language_changed():
            self.change_language(languages.currentData())
            localize()

        def theme_changed(index):
            self.theme = index
            self.settings.setValue('theme', index)
            self.apply_theme()

        languages.currentIndexChanged.connect(language_changed)
        themes.currentIndexChanged.connect(theme_changed)
        localize()
        return dialog

    def show_settings(self):
        if self.work:
            return
        dialog = self.settings_dialog()
        dialog.exec()
        dialog.deleteLater()

    def check_update(self,manual=False):
        if self.update_thread or self.work:return
        if not manual and (not self.settings.value('automaticUpdates',True,type=bool) or time.time()-float(self.settings.value('lastUpdateCheck',0))<86400):return
        thread=QThread(self);worker=Worker('update',None);worker.moveToThread(thread);self.update_thread=thread;self.update_worker=worker;thread.started.connect(worker.run)
        worker.done.connect(lambda v:self.update_result(v,manual));worker.error.connect(lambda e:self.update_error(e,manual));worker.finished.connect(thread.quit);worker.finished.connect(worker.deleteLater);thread.finished.connect(self.update_finished);thread.finished.connect(thread.deleteLater);thread.start()
    def update_finished(self):self.update_thread=None;self.update_worker=None
    def update_error(self,error,manual):
        if manual:QMessageBox.information(self,'MediaKeep',self.t('Could not check for updates. Please try again later.'))
    def update_result(self,result,manual):
        self.settings.setValue('lastUpdateCheck',time.time())
        if not result:
            if manual:QMessageBox.information(self,'MediaKeep',self.t('MediaKeep is up to date.'))
            return
        if not manual and self.settings.value('skippedVersion','')==result['version']:return
        box=QMessageBox(self);box.setWindowTitle('MediaKeep');box.setText(self.t('A new MediaKeep version is available'));box.setInformativeText(result['version']+'\n'+result['notes'][:1800]);download=box.addButton(self.t('Download Update'),QMessageBox.AcceptRole);skip=box.addButton(self.t('Skip This Version'),QMessageBox.RejectRole);box.addButton(self.t('Later'),QMessageBox.RejectRole);box.exec()
        if box.clickedButton()==download:QDesktopServices.openUrl(QUrl(result['url']))
        elif box.clickedButton()==skip:self.settings.setValue('skippedVersion',result['version'])
    def about(self):QMessageBox.about(self,self.t('About MediaKeep'),f'MediaKeep {VERSION}\nApple Craft / 사과공방\nChoi Kuidong / 최귀동\nNovember 2026\nhttps://applecraft.kr\n© 2026 Apple Craft. All rights reserved.')
    def closeEvent(self,event):
        if self.work:
            if QMessageBox.question(self,'MediaKeep',self.t('Cancel')+'?')==QMessageBox.Yes:self.closing=True;self.cancel_work()
            event.ignore();return
        if self.update_thread:
            self.update_thread.quit();self.update_thread.wait(22000)
        self.player.stop();event.accept()

def main():
    app=QApplication(sys.argv);app.setApplicationName('MediaKeep');app.setApplicationVersion(VERSION);app.setOrganizationName('AppleCraft');app.setWindowIcon(QIcon(str(RESOURCE/'MediaKeep.png')))
    for font in ['NotoSans.ttf','NotoSansCJK-Regular.otf']:
        ident=QFontDatabase.addApplicationFont(str(RESOURCE/'fonts'/font))
        if ident<0:raise RuntimeError('Could not load bundled font: '+font)
    app.setFont(QFont('Noto Sans',10))
    if '--self-test' in sys.argv:
        from verify import run
        return run(app)
    window=Window();window.show();return app.exec()
if __name__=='__main__':sys.exit(main())
