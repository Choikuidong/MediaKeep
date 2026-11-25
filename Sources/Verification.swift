import Cocoa
func renderInterfaceTests() {
_ = NSApplication.shared
let owner=App()
owner.buildInterface()
precondition(owner.videoMode && owner.resolution.indexOfSelectedItem==0)
let defaults=UserDefaults.standard
let savedTheme=defaults.object(forKey:"theme"), savedLang=defaults.object(forKey:"appLanguage")
let savedFolders=defaults.object(forKey:"favoriteFolders"),savedDestination=defaults.object(forKey:"destination")
defer {defaults.set(savedTheme,forKey:"theme");defaults.set(savedLang,forKey:"appLanguage");defaults.set(savedFolders,forKey:"favoriteFolders");defaults.set(savedDestination,forKey:"destination")}
if ProcessInfo.processInfo.environment["MEDIAKEEP_DOC_SCREENSHOTS"] == "1" {
 owner.destination=URL(fileURLWithPath:"/Users/demo/Downloads")
 owner.favorites=[["path":"/Users/demo/Downloads","alias":"Downloads"],["path":"/Users/demo/Movies","alias":"Movies"],["path":"/Users/demo/Music","alias":"Music"]]
}
for lang in supportedLanguages.map({ $0.code }) {
 defaults.set(lang,forKey:"appLanguage")
 for theme in Palette.titles.indices {
  defaults.set(theme,forKey:"theme");owner.buildInterface()
  precondition(owner.folderButtons.count==9)
  precondition(owner.subtitleCode(owner.videoLanguage)==lang)
  precondition(owner.audioPreference(owner.videoAudio)==languageInfo(lang).audio)
  precondition(owner.appLanguage.superview == nil)
  if theme == 2 {
   owner.showSettings()
   precondition(owner.appLanguage.titleOfSelectedItem == languageInfo(lang).name)
   precondition(owner.appearancePicker.numberOfItems == 7)
   let support = owner.settingsWindow!.contentView!.subviews.last!
   precondition(support.subviews.contains { $0 is NSImageView } == (lang == "ko"))
   owner.settingsWindow?.close()
   owner.settingsWindow = nil
   owner.appLanguage.removeFromSuperview()
  }
  for (i,option) in supportedLanguages.enumerated() {
   owner.videoLanguage.selectItem(at:i+1);precondition(owner.subtitleCode(owner.videoLanguage)==option.code)
   owner.videoAudio.selectItem(at:i+2);precondition(owner.audioPreference(owner.videoAudio)==option.audio)
  }
  owner.videoLanguage.selectItem(at:0);owner.videoAudio.selectItem(at:0)
  for tab in 0...1 {
   owner.tabs.selectedSegment=tab;owner.changeTab();owner.window.contentView!.layoutSubtreeIfNeeded()
   let view=owner.window.contentView!
   for button in owner.folderButtons+[owner.convert,owner.reveal] {precondition(view.bounds.contains(button.convert(button.bounds,to:view)))}
   owner.window.appearance!.performAsCurrentDrawingAppearance {
    let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:bitmap)
    try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:(ProcessInfo.processInfo.environment["MEDIAKEEP_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())+"/mediakeep-\(lang)-\(theme)-\(tab).png"))
   }
  }
 }
}
precondition(AppVersion("v1.10.0")!>AppVersion("1.2.0")!)
precondition(AppVersion("1.2")==AppVersion("1.2.0"))
precondition(AppVersion("1.3.0-beta")==nil)
print("PASS: 7 themes × 20 languages × 2 tabs; 9 visible shortcuts and actions; subtitle language follows app; release version comparisons")

}

func testUpdates() {
    precondition(supportedLanguages.count==20)
    precondition(Set(supportedLanguages.map{$0.code}).count==20)
    let properNames:Set<String>=["MediaKeep","Apple Craft"]
    for lang in supportedLanguages where !["en","ko"].contains(lang.code) {
        guard let catalog=translations[lang.code] else {preconditionFailure("Missing catalog: "+lang.code)}
        for key in englishStrings.values where !properNames.contains(key) {
            precondition(catalog[key]?.isEmpty==false,"Missing translation: "+lang.code+" / "+key)
        }
        precondition(catalog["Video Download"]?.isEmpty==false)
    }
    precondition(subtitleLanguages("zh-Hans").contains("zh-CN"))
    precondition(subtitleLanguages("zh-Hant").contains("zh-TW"))
    precondition(subtitleLanguages("pt-BR").contains("pt-BR,pt"))
    precondition(languageInfo("ja").iso639=="jpn" && languageInfo("zh-Hant").iso639=="zho")
    precondition(languageInfo("unknown").code=="en")
    print("PASS: 20 language definitions, complete runtime translations, subtitle aliases and ISO language metadata")
    precondition(AppVersion("v1.10.0")! > AppVersion("1.2.0")!)
    precondition(AppVersion("1.2") == AppVersion("1.2.0"))
    precondition(AppVersion("1.3.0-beta") == nil)
    let good=UpdateRelease.Asset(name:"MediaKeep-1.3.0-arm64.dmg",browser_download_url:URL(string:"https://github.com/Choikuidong/MediaKeep/releases/download/v1.3.0/MediaKeep-1.3.0-arm64.dmg")!,size:100,state:"uploaded")
    let bad=UpdateRelease.Asset(name:good.name,browser_download_url:URL(string:"https://example.com/file.dmg")!,size:100,state:"uploaded")
    precondition(UpdateRelease(tag_name:"v1.3.0",body:nil,draft:false,prerelease:false,assets:[good]).download != nil)
    precondition(UpdateRelease(tag_name:"v1.3.0",body:nil,draft:false,prerelease:false,assets:[bad]).download == nil)
    precondition(UpdateRelease(tag_name:"v1.3.0",body:nil,draft:false,prerelease:false,assets:[]).download == nil)
    print("PASS: numeric version ordering; invalid versions; approved repository asset URLs; missing installers")
}

func testLocalConversion() throws {
    _ = NSApplication.shared
    let app=App();app.buildInterface();app.tabs.selectedSegment=1;app.changeTab()
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("MediaKeep-test-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:root)}
    let originalDestination=app.destination, originalFavorites=app.favorites
    defer {app.destination=originalDestination;app.favorites=originalFavorites;app.refreshFolders()}
    let input=root.appendingPathComponent("input.mp4"),sub=root.appendingPathComponent("input.srt")
    let generator=Process();generator.executableURL=Bundle.main.url(forResource:"ffmpeg",withExtension:nil)
    generator.arguments=["-nostdin","-loglevel","error","-f","lavfi","-i","color=c=blue:s=320x180:d=2","-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-c:a","aac","-shortest",input.path]
    try generator.run();generator.waitUntilExit();precondition(generator.terminationStatus==0)
    try "1\n00:00:00,000 --> 00:00:01,500\nMediaKeep test\n".write(to:sub,atomically:true,encoding:.utf8)
    app.source=input;app.captionSource=sub;app.destination=root;app.nameField.stringValue="Converted";app.captions.state = .on;app.saveMP3()
    let deadline=Date().addingTimeInterval(45)
    while app.busy && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.05))}
    precondition(!app.busy,"Local conversion timed out")
    for ext in ["mp3","srt","lrc"] {precondition(FileManager.default.fileExists(atPath:root.appendingPathComponent("Converted."+ext).path),app.status.stringValue)}
    let srt=try String(contentsOf:root.appendingPathComponent("Converted.srt")),lrc=try String(contentsOf:root.appendingPathComponent("Converted.lrc"))
    precondition(srt.contains("MediaKeep test") && lrc.contains("[00:00.00]MediaKeep test"))
    precondition(app.reveal.isEnabled)
    print("PASS: App workflow converts local video to MP3 + SRT + LRC, preserves captions, and enables Reveal saved file")
}
