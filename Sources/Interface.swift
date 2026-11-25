import Cocoa
final class PrimaryButton:NSButton {
    var fill=NSColor.systemIndigo
    var ink=NSColor.white
    override func draw(_ dirtyRect:NSRect) {
        (isEnabled ? fill:fill.withAlphaComponent(0.35)).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:8,yRadius:8).fill()
        let value=NSAttributedString(string:title,attributes:[.font:font ?? NSFont.systemFont(ofSize:15,weight:.semibold),.foregroundColor:ink])
        let size=value.size();value.draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2))
    }
}

struct Palette {
    let background: NSColor, card: NSColor, text: NSColor, secondary: NSColor, accent: NSColor, border: NSColor
    let dark: Bool
    static func color(_ hex: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((hex >> 16)&255)/255, green: CGFloat((hex >> 8)&255)/255, blue: CGFloat(hex&255)/255, alpha: 1) }
    static let titles = [("Midnight Blue","미드나이트 블루"), ("Warm Amber","웜 앰버"), ("Soft Light","소프트 라이트"), ("Forest Green","포레스트 그린"), ("Lavender Night","라벤더 나이트"), ("Ocean Teal","오션 틸"), ("Peach Cream","피치 크림")]
    static func make(_ index: Int) -> Palette {
        let values: [(UInt32,UInt32,UInt32,UInt32,UInt32,UInt32,Bool)] = [
            (0x101c30,0x1b2b42,0xf4f7ff,0xb8c5d9,0x299fff,0x35465d,true),
            (0x221e1b,0x302a25,0xfff8ed,0xcbbfb0,0xffbb37,0x51463b,true),
            (0xf3f4f8,0xffffff,0x192033,0x566176,0x4338ca,0xdce0e9,false),
            (0x10251e,0x1e352c,0xf3fff8,0xb8cdbf,0x84eba3,0x385647,true),
            (0x1b1726,0x282234,0xeae1f6,0xbdb0ce,0xc9a8ff,0x4a3e59,true),
            (0x101f24,0x172b30,0xe4f1ef,0xb4cbca,0x68ded0,0x315158,true),
            (0xf7eee8,0xfff9f5,0x322521,0x715a50,0xa33d32,0xe1cfc4,false)]
        let c = values[values.indices.contains(index) ? index : 2]
        return Palette(background: color(c.0),card: color(c.1),text: color(c.2),secondary: color(c.3),accent: color(c.4),border: color(c.5),dark:c.6)
    }
}
final class FolderShortcut: NSButton, NSDraggingSource {
    var move: ((Int,Int)->Void)?
    static let type = NSPasteboard.PasteboardType("kr.applecraft.mediakeep.folder")
    override init(frame: NSRect) { super.init(frame:frame); registerForDraggedTypes([Self.type]) }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        while let next = window?.nextEvent(matching: [.leftMouseDragged,.leftMouseUp]) {
            if next.type == .leftMouseUp { _ = target?.perform(action, with:self); return }
            if hypot(next.locationInWindow.x-event.locationInWindow.x,next.locationInWindow.y-event.locationInWindow.y)>5 {
                let item=NSPasteboardItem(); item.setString(String(tag),forType:Self.type)
                let drag=NSDraggingItem(pasteboardWriter:item)
                let image=NSImage(size:bounds.size); image.lockFocus(); draw(bounds); image.unlockFocus()
                drag.setDraggingFrame(bounds,contents:image)
                beginDraggingSession(with:[drag],event:next,source:self); return
            }
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { isEnabled && sender.draggingPasteboard.string(forType:Self.type) != nil ? .move : [] }
    override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool { isEnabled }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard let value=sender.draggingPasteboard.string(forType:Self.type), let from=Int(value) else {return false}
        move?(from,tag); return true
    }
}

extension App {
    var palette: Palette { Palette.make(UserDefaults.standard.object(forKey:"theme") as? Int ?? 2) }
    func buildInterface() {
        let p=palette
        let first = window == nil
        if first {
            window=InputWindow(contentRect:NSRect(x:0,y:0,width:1080,height:770),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
            window.center()
            tabs.selectedSegment=0
            if let path=UserDefaults.standard.string(forKey:"destination"),FileManager.default.fileExists(atPath:path) {destination=URL(fileURLWithPath:path)}
            favorites=Array((UserDefaults.standard.array(forKey:"favoriteFolders") as? [[String:String]] ?? [["path":destination.path,"alias":""]]).filter{$0["path"] != nil}.prefix(9))
            quality.selectItem(at:1); rangePicker.selectedSegment=0
        }
        let tab=max(0,tabs.selectedSegment), sourceMode=max(0,mode.selectedSegment)
        let q=quality.numberOfItems==0 ? 1 : quality.indexOfSelectedItem
        let res=resolution.numberOfItems==0 ? 0 : resolution.indexOfSelectedItem
        let sl=language.numberOfItems==0 ? 0 : language.indexOfSelectedItem
        let vl=videoLanguage.numberOfItems==0 ? 0 : videoLanguage.indexOfSelectedItem
        let va=videoAudio.numberOfItems==0 ? 0 : videoAudio.indexOfSelectedItem
        let aa=audioTrack.numberOfItems==0 ? 0 : audioTrack.indexOfSelectedItem
        window.title="MediaKeep"; window.titlebarAppearsTransparent=true
        window.appearance=NSAppearance(named:p.dark ? .darkAqua : .aqua); window.backgroundColor=p.background
        let canvas=FlippedDocument(frame:NSRect(x:0,y:0,width:1080,height:770)); canvas.wantsLayer=true; canvas.layer?.backgroundColor=p.background.cgColor;window.contentView=canvas
        audioCards=[]; folderButtons=[]
        func place(_ v:NSView,_ parent:NSView,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat) {v.removeFromSuperview();v.translatesAutoresizingMaskIntoConstraints=true;v.frame=NSRect(x:x,y:y,width:w,height:h);parent.addSubview(v)}
        func label(_ en:String,_ ko:String,_ parent:NSView,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ size:CGFloat=12,_ accent:Bool=false) {
            let v=NSTextField(labelWithString:T(en,ko));v.font = .systemFont(ofSize:size,weight:accent ? .semibold : .regular);v.textColor=accent ? p.accent : p.secondary;v.lineBreakMode = .byTruncatingTail;v.toolTip=v.stringValue;place(v,parent,x,y,w,size+8)
        }
        func card(_ en:String,_ ko:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat)->NSView {
            let v=FlippedDocument();v.wantsLayer=true;v.layer?.backgroundColor=p.card.cgColor;v.layer?.cornerRadius=12;v.layer?.borderWidth=1;v.layer?.borderColor=p.border.cgColor;place(v,canvas,x,y,w,h)
            label(en,ko,v,18,13,w-36,15,true); return v
        }
        func button(_ v:NSButton,_ title:String,_ act:Selector,_ parent:NSView,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat=30) {
            v.title=title;v.target=self;v.action=act;v.bezelStyle = .rounded;v.font = .systemFont(ofSize:11,weight:.medium);v.cell?.lineBreakMode = .byTruncatingTail;v.toolTip=title;v.contentTintColor=p.text;place(v,parent,x,y,w,h)
        }
        func popup(_ v:NSPopUpButton,_ items:[String],_ index:Int,_ parent:NSView,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat) {
            v.font = .systemFont(ofSize:11);v.removeAllItems();v.addItems(withTitles:items);v.selectItem(at:max(0,index));place(v,parent,x,y,w,28)
        }
        func field(_ v:NSTextField,_ placeholder:String,_ parent:NSView,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat) {v.placeholderString=placeholder;v.textColor=p.text;v.backgroundColor=p.card;v.font = .systemFont(ofSize:12);place(v,parent,x,y,w,27)}
        let icon=NSImageView();icon.image=Bundle.main.url(forResource:"MediaKeep",withExtension:"png").flatMap{NSImage(contentsOf:$0)};icon.imageScaling = .scaleProportionallyUpOrDown;place(icon,canvas,24,13,44,44)
        label("MediaKeep","MediaKeep",canvas,78,13,260,26,true)
        label("Save videos. Extract audio.","영상을 저장하고, 소리를 추출하세요.",canvas,80,48,380)
        button(settingsButton,T("Settings…","설정…"),#selector(showSettings),canvas,948,18,108)
        tabs.setLabel(T("Video Download","동영상 다운로드"),forSegment:0);tabs.setLabel(T("Audio Extraction","오디오 추출"),forSegment:1)
        tabs.font = .systemFont(ofSize:12);tabs.setWidth(215,forSegment:0);tabs.setWidth(215,forSegment:1);tabs.selectedSegment=tab;tabs.target=self;tabs.action=#selector(changeTab);place(tabs,canvas,315,77,450,34)
        let sourceCard=card("01  Video source","01  가져올 영상",24,124,510,114)
        mode.setLabel(T("Local video","내 동영상"),forSegment:0);mode.setLabel(T("YouTube link","유튜브 링크"),forSegment:1);mode.selectedSegment=sourceMode;mode.target=self;mode.action=#selector(changeMode);place(mode,sourceCard,16,38,478,26)
        localPicker=FlippedDocument();place(localPicker,sourceCard,16,73,478,28)
        button(choose,L("동영상 선택…"),#selector(selectFile),localPicker,0,0,130,26);files.textColor=p.secondary;files.lineBreakMode = .byTruncatingMiddle;place(files,localPicker,140,4,338,22)
        field(link,T("Paste a YouTube video link","유튜브 링크를 붙여 넣으세요"),sourceCard,16,73,478)
        let settings=card("02  Audio settings","02  오디오 설정",24,250,510,166)
        label("MP3 quality","MP3 음질",settings,16,45,130)
        popup(quality,["320 kbps · ~2.4 MB/min","192 kbps · ~1.4 MB/min","128 kbps · ~1.0 MB/min"],q,settings,156,38,338)
        captions.title=T("Save subtitles","자막 함께 저장");place(captions,settings,16,75,170,24)
        let langs=[T("App language","앱 언어와 동일")]+supportedLanguages.map{ $0.name }
        popup(language,langs,sl,settings,216,70,278)
        label("Audio track","음성 선택",settings,16,110,130);popup(audioTrack,audioChoices,aa,settings,156,102,338)
        button(chooseCaption,L("자막 파일 선택…"),#selector(selectCaption),settings,16,133,150,26);button(clearCaption,L("자막 해제"),#selector(resetCaption),settings,176,133,80,26)
        captionLabel.textColor=p.secondary;captionLabel.font = .systemFont(ofSize:10);captionLabel.lineBreakMode = .byTruncatingMiddle;place(captionLabel,settings,266,138,228,18)
        audioCards=[sourceCard,settings]
        videoCard=card("01  Video source","01  가져올 영상",24,124,510,292)
        field(videoLink,T("Paste a YouTube video link","유튜브 링크를 붙여 넣으세요"),videoCard,16,45,478)
        label("02  Video settings","02  동영상 설정",videoCard,18,93,470,15,true)
        label("Quality","화질",videoCard,16,136,120)
        popup(resolution,["4K · "+T("Up to","최대")+" 2160p","Full HD · "+T("Up to","최대")+" 1080p","HD · "+T("Up to","최대")+" 720p","SD · "+T("Up to","최대")+" 480p"],res,videoCard,156,128,338)
        videoSubs.title=T("Save subtitles","자막 함께 저장");place(videoSubs,videoCard,16,171,190,24)
        popup(videoLanguage,langs,vl,videoCard,216,166,278)
        label("Audio track","음성 선택",videoCard,16,214,120);popup(videoAudio,audioChoices,va,videoCard,156,205,338)
        label("Matching dub preferred; original audio used if unavailable.","선택한 언어 더빙을 우선 사용하며, 없으면 원본 음성으로 저장합니다.",videoCard,16,250,478,11)
        let range=card("Save range","저장 구간",24,428,510,93)
        rangePicker.setLabel(T("Entire video","전체"),forSegment:0);rangePicker.setLabel(T("Custom range","구간 지정"),forSegment:1);rangePicker.target=self;rangePicker.action=#selector(changeInlineRange);place(rangePicker,range,16,36,228,28)
        field(beginField,T("Start 00:00","시작 00:00"),range,254,38,116);field(endField,T("End 00:00","종료 00:00"),range,378,38,116)
        label("Without a range, the entire video is saved.","구간을 지정하지 않으면 영상 전체를 저장합니다.",range,16,69,478,11)
        let folder=card("03  Save location","03  받을 위치",24,533,510,196)
        button(NSButton(),T("Choose folder…","다른 폴더…"),#selector(chooseFolder),folder,352,6,142)
        folderLabel.textColor=p.secondary;folderLabel.font = .systemFont(ofSize:11);folderLabel.lineBreakMode = .byTruncatingMiddle;place(folderLabel,folder,16,40,478,19)
        for i in 0..<9 {
            let item=FolderShortcut(frame:.zero);item.tag=i;item.setButtonType(.pushOnPushOff)
            item.move={ [weak self] from,to in self?.moveFolder(from,to) }
            button(item,"",#selector(favorite(_:)),folder,16+CGFloat(i%3)*162,64+CGFloat(i/3)*30,154,28);folderButtons.append(item)
        }
        button(NSButton(),T("Edit names","별명·위치 편집"),#selector(editFavorites),folder,16,158,124,28)
        label("Drag to reorder · Up to 9 locations","드래그로 순서 변경 · 최대 9개",folder,150,165,344,11)
        refreshFolders()
        playbackCard=card("Preview","미리보기",550,124,506,361)
        button(inspect,L("미리보기 불러오기"),#selector(inspectSource),playbackCard,330,6,160)
        screen.controlsStyle = .inline;place(screen,playbackCard,16,48,474,247)
        artwork.imageScaling = .scaleProportionallyUpOrDown;place(artwork,playbackCard,16,48,474,247)
        artwork.isHidden=artwork.image == nil;screen.isHidden=artwork.image != nil
        playbackNote.textColor=p.secondary;playbackNote.font = .systemFont(ofSize:11);playbackNote.maximumNumberOfLines=1;place(playbackNote,playbackCard,16,302,474,20)
        button(NSButton(),T("▷ Preview original","▷ 원본 미리보기"),#selector(playPreview),playbackCard,155,327,196,28)
        let save=card("Save file","파일 저장",550,497,506,232)
        field(nameField,T("Automatically use the video title","영상 제목으로 자동 지정"),save,16,44,474)
        status.textColor=p.secondary;status.font = .systemFont(ofSize:12);status.maximumNumberOfLines=2;place(status,save,16,82,474,38)
        meter.style = .bar;meter.minValue=0;meter.maxValue=100;meter.isIndeterminate=false;place(meter,save,16,121,442,10);meter.isHidden=true
        progress.style = .spinning;progress.isDisplayedWhenStopped=false;place(progress,save,466,115,18,18)
        button(convert,"",#selector(saveMP3),save,16,138,354,39);convert.fill=p.accent;convert.ink=p.dark ? .black : .white;convert.font = .systemFont(ofSize:15,weight:.semibold)
        button(cancel,L("취소"),#selector(stop),save,380,138,110,39);cancel.isHidden=true
        button(reveal,L("저장된 파일 보기"),#selector(revealOutput),save,16,184,474,34);reveal.isEnabled=lastOutput != nil
        label("Please download only content you have permission to use. You are responsible for your use.","다운로드할 권한이 있는 콘텐츠에만 이용해 주세요. 이용에 따른 책임은 사용자에게 있습니다.",canvas,24,747,1032,11)
        if source == nil {files.stringValue=L("선택한 동영상이 없습니다")}
        if captionSource == nil {captionLabel.stringValue=L("자막 파일 없음 · 유튜브 모드에서는 온라인 자막 사용")}
        if previewURL == nil {playbackNote.stringValue=L("다운로드를 시작하면 여기에 영상이 표시됩니다.")}
        changeMode();changeTab();changeInlineRange()
        convert.frame.size.width=474
        if first {captions.state = .on;videoSubs.state = .on}
        setupMenu();window.makeKeyAndOrderFront(nil)
    }
    func moveFolder(_ from:Int,_ to:Int) {
        guard !busy,from != to,favorites.indices.contains(from),(0..<9).contains(to) else { return }
        let value=favorites.remove(at:from);favorites.insert(value,at:min(to,favorites.count));refreshFolders()
    }
    var audioChoices:[String] { [T("App language · Prefer dub","앱 언어 더빙 우선"),T("Original audio","원본 음성")]+supportedLanguages.map{$0.name} }
    func subtitleCode(_ picker:NSPopUpButton)->String {let i=picker.indexOfSelectedItem;return i<=0 ? currentLanguage:supportedLanguages[min(i-1,supportedLanguages.count-1)].code}
    func audioPreference(_ picker:NSPopUpButton)->String? {
        let i=picker.indexOfSelectedItem
        if i==1{return nil}
        return languageInfo(i<=0 ? currentLanguage:supportedLanguages[min(i-2,supportedLanguages.count-1)].code).audio
    }
    var currentLanguage:String {selectedLanguage}
    @objc func changeAppLanguage() {
        guard !busy, supportedLanguages.indices.contains(appLanguage.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(supportedLanguages[appLanguage.indexOfSelectedItem].code, forKey: "appLanguage")
        closeAbout()
        refreshSettings()
    }
    func setupMenu() {
        let menu=NSMenu();let item=menu.addItem(withTitle:"MediaKeep",action:nil,keyEquivalent:"");let appMenu=NSMenu();item.submenu=appMenu
        for (title,action,key) in [(T("About MediaKeep","MediaKeep에 관하여"),#selector(showAbout),""),(T("Settings…","설정…"),#selector(showSettings),","),(T("Check for Updates…","업데이트 확인…"),#selector(manualUpdateCheck),"")] {let i=appMenu.addItem(withTitle:title,action:action,keyEquivalent:key);i.target=self}
        appMenu.addItem(.separator());appMenu.addItem(withTitle:T("Quit MediaKeep","MediaKeep 종료"),action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");NSApp.mainMenu=menu
    }
    @objc func showSettings() {
        guard !busy else{return}
        if let w=settingsWindow {w.makeKeyAndOrderFront(nil);return}
        let p = palette
        let korean = currentLanguage == "ko"
        let height: CGFloat = korean ? 477 : 453
        let w = InputWindow(contentRect: NSRect(x:0,y:0,width:510,height:height), styleMask:[.titled,.closable], backing:.buffered, defer:false)
        w.isReleasedWhenClosed = false
        w.title = T("MediaKeep Settings","MediaKeep 설정")
        w.appearance = window.appearance
        w.backgroundColor = p.background
        let view = FlippedDocument(frame:NSRect(x:0,y:0,width:510,height:height))
        w.contentView = view

        func label(_ parent: NSView, _ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ size: CGFloat = 13, _ color: NSColor? = nil, _ weight: NSFont.Weight = .regular, height: CGFloat = 21) {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize:size,weight:weight)
            field.textColor = color ?? p.secondary
            field.frame = NSRect(x:x,y:y,width:width,height:height)
            parent.addSubview(field)
        }
        func picker(_ control: NSPopUpButton, _ titles: [String], _ index: Int, _ y: CGFloat, _ action: Selector) {
            control.removeAllItems()
            control.addItems(withTitles:titles)
            control.selectItem(at:index)
            control.target = self
            control.action = action
            control.frame = NSRect(x:24,y:y,width:462,height:28)
            view.addSubview(control)
        }
        label(view,T("App language","앱 언어"),24,19,462,14,p.text,.semibold)
        picker(appLanguage,supportedLanguages.map { $0.name },supportedLanguages.firstIndex { $0.code == currentLanguage } ?? 0,44,#selector(changeAppLanguage))
        label(view,T("Changes apply immediately across the app.","선택하면 앱 화면에 바로 적용됩니다."),24,78,462,12)
        label(view,T("Appearance","화면 색상"),24,109,462,14,p.text,.semibold)
        let theme = UserDefaults.standard.object(forKey:"theme") as? Int ?? 2
        picker(appearancePicker,Palette.titles.map { T($0.0,$0.1) },Palette.titles.indices.contains(theme) ? theme : 2,133,#selector(changeTheme))
        autoUpdate.title = T("Automatically check for updates","자동으로 업데이트 확인")
        autoUpdate.state = UserDefaults.standard.object(forKey:"automaticUpdates") as? Bool == false ? .off : .on
        autoUpdate.target = self
        autoUpdate.action = #selector(toggleUpdates)
        autoUpdate.frame = NSRect(x:24,y:178,width:462,height:26)
        view.addSubview(autoUpdate)
        label(view,T("Checks on launch and daily while the app is running.","앱 실행 시와 실행 중 하루에 한 번 확인합니다."),24,208,462,12)
        let update = NSButton(title:T("Check for Updates…","업데이트 확인…"),target:self,action:#selector(manualUpdateCheck))
        update.bezelStyle = .rounded
        update.frame = NSRect(x:24,y:232,width:240,height:32)
        view.addSubview(update)
        label(view,"GitHub · Choikuidong/MediaKeep",24,274,462,12)

        let support = FlippedDocument(frame:NSRect(x:24,y:308,width:462,height:height-328))
        support.wantsLayer = true
        support.layer?.backgroundColor = p.card.cgColor
        support.layer?.borderColor = p.border.cgColor
        support.layer?.borderWidth = 1
        support.layer?.cornerRadius = 12
        view.addSubview(support)
        let textWidth: CGFloat = korean ? 294 : 420
        label(support,T("Support MediaKeep","MediaKeep 개발을 응원해 주세요"),16,15,textWidth,16,p.accent,.semibold)
        label(support,T("If MediaKeep saves you time, you can help fund future updates.","도움이 되셨다면 다음 업데이트를 응원해 주세요."),16,43,textWidth,12,height:32)
        label(support,T("MediaKeep is free to use, with or without sponsorship.","후원은 선택이며, 앱은 누구나 무료로 이용하실 수 있습니다."),16,73,textWidth,12,height:30)
        let sponsor = NSButton(title:T("Support on GitHub ↗","GitHub에서 후원하기 ↗"),target:self,action:#selector(openSponsors))
        sponsor.bezelStyle = .rounded
        sponsor.frame = NSRect(x:16,y:103,width:240,height:30)
        support.addSubview(sponsor)
        if korean, let url = Bundle.main.url(forResource:"KakaoPay",withExtension:"png"), let image = NSImage(contentsOf:url) {
            let qr = NSImageView(frame:NSRect(x:329,y:10,width:116,height:116))
            qr.image = image
            qr.imageScaling = .scaleProportionallyUpOrDown
            qr.setAccessibilityLabel("카카오페이 후원 QR 코드")
            support.addSubview(qr)
            label(support,"카카오페이로 후원하기",329,128,117,11,p.secondary,.medium)
        }
        settingsWindow = w
        w.center()
        w.makeKeyAndOrderFront(nil)
    }
    @objc func openSponsors() {
        guard let url = URL(string:"https://github.com/sponsors/Choikuidong") else { return }
        NSWorkspace.shared.open(url)
    }
    private func refreshSettings() {
        settingsWindow?.close()
        settingsWindow = nil
        buildInterface()
        showSettings()
    }
    @objc func changeTheme() {
        guard !busy, Palette.titles.indices.contains(appearancePicker.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(appearancePicker.indexOfSelectedItem,forKey:"theme")
        refreshSettings()
    }
    @objc func toggleUpdates(){UserDefaults.standard.set(autoUpdate.state == .on,forKey:"automaticUpdates")}
}
extension String {var nilIfEmpty:String? {isEmpty ? nil:self}}

func audioFormat(language:String?)->String {
    guard let l=language else{return "bestaudio[format_note*=original]/bestaudio/best"}
    return "bestaudio[language^=\(l)]/best[language^=\(l)]/bestaudio[format_note*=original]/bestaudio/best"
}
func videoFormat(height:Int,language:String?,compatible:Bool=false)->String {
    let v="bv[height<=\(height)]"+(compatible ? "[ext=mp4]":""), b="b[height<=\(height)]"+(compatible ? "[ext=mp4]":"")
    let original="\(v)+ba[format_note*=original]/\(v)+ba/\(b)"
    if let l=language {return "\(v)+ba[language^=\(l)]/\(b)[language^=\(l)]/"+original}
    return original
}
