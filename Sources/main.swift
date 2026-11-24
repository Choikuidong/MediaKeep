import Cocoa
import AVKit
import AVFoundation
import UniformTypeIdentifiers

func lrcFromSRT(_ text: String) -> String {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
    let regex = try! NSRegularExpression(pattern: #"(\d{2,}):(\d{2}):(\d{2})[,.](\d{3})\s*-->[^\n]*\n([\s\S]*?)(?=\n\s*\n|$)"#)
    let ns = normalized as NSString
    return regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)).map { match in
        func part(_ n: Int) -> String { ns.substring(with: match.range(at: n)) }
        let minutes = (Int(part(1))! * 60) + Int(part(2))!
        let clean = part(5).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).components(separatedBy: .newlines).joined(separator: " ")
        return String(format: "[%02d:%02d.%02d]", minutes, Int(part(3))!, Int(part(4))! / 10) + clean
    }.joined(separator: "\n") + "\n"
}

struct Clip {
    let start: Double
    let end: Double
    var seek: [String] { ["-ss", String(start)] }
    var limit: [String] { ["-t", String(end - start)] }
    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            guard let n = Double(part), n.isFinite, n >= 0, index == 0 || n < 60 else { return nil }
            total = total * 60 + n
        }
        return total.isFinite && total <= 315360000 ? total : nil
    }
    func align(_ file: URL) throws {
        let source = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
        var cues: [String] = []
        func stamp(_ seconds: Double) -> String {
            let ms = Int((seconds * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms/3600000, ms/60000%60, ms/1000%60, ms%1000)
        }
        for block in source.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }
            let times = lines[1].replacingOccurrences(of: ",", with: ".").components(separatedBy: " --> ")
            guard times.count == 2, let a = Clip.seconds(times[0]), let b = Clip.seconds(times[1]), min(end,b) > max(start,a) else { continue }
            cues.append("\(cues.count+1)\n" + stamp(max(start,a)-start) + " --> " + stamp(min(end,b)-start) + "\n" + lines.dropFirst(2).joined(separator: "\n").trimmingCharacters(in: .newlines))
        }
        try cues.joined(separator: "\n\n").write(to: file, atomically: true, encoding: .utf8)
    }
}

// Keep standard text shortcuts available through the active field editor.
final class InputWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, let editor = firstResponder as? NSTextView {
            switch event.charactersIgnoringModifiers {
            case "v": editor.paste(self)
            case "c": editor.copy(self)
            case "x": editor.cut(self)
            case "a": editor.selectAll(self)
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class FlippedDocument: NSView { override var isFlipped: Bool { true } }

class App: NSObject, NSApplicationDelegate {
    let appLanguage = NSPopUpButton()
    let appearancePicker = NSPopUpButton()
    let videoAudio = NSPopUpButton()
    let audioTrack = NSPopUpButton()
    let settingsButton = NSButton()
    let autoUpdate = NSButton(checkboxWithTitle: "", target:nil, action:nil)
    var settingsWindow: NSWindow?
    var updateTimer: Timer?
    var updateChecking = false
    let tabs = NSSegmentedControl(labels: [L("동영상 다운로드"), L("오디오 추출")], trackingMode: .selectOne, target: nil, action: nil)
    let videoLink = NSTextField(string: "")
    let videoSubs = NSButton(checkboxWithTitle: L("선택형 자막 포함 + SRT 저장"), target: nil, action: nil)
    let videoLanguage = NSPopUpButton()
    let resolution = NSPopUpButton()
    var audioCards: [NSView] = []
    var videoCard: NSView!
    var playbackCard: NSView!
    let screen = AVPlayerView()
    let playbackNote = NSTextField(wrappingLabelWithString: L("다운로드를 시작하면 여기에 영상이 표시됩니다."))
    var sampleGeneration = UUID()
    var sampleTask: Process?
    var sampleFile: URL?
    func clearSample() {
        sampleGeneration = UUID()
        if let task = sampleTask, task.isRunning { task.terminate() }
        sampleTask = nil
        screen.player?.pause()
        screen.player = nil
        if let file = sampleFile { try? FileManager.default.removeItem(at: file) }
        sampleFile = nil
    }
    func startSample(in folder: URL, clip: Clip?) {
        clearSample()
        playbackNote.stringValue = L("첫 영상 데이터를 기다리는 중…")
        let generation = sampleGeneration
        func attempt() {
            guard generation == sampleGeneration, !cancelled, busy else { return }
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            let candidates = files.filter {
                $0.lastPathComponent.hasPrefix("result.") && ($0.lastPathComponent.contains(".mp4") || $0.lastPathComponent.contains(".webm")) &&
                ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 131072
            }
            guard let media = candidates.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { attempt() }
                return
            }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            let task = Process()
            task.executableURL = Bundle.main.resourceURL!.appendingPathComponent("ffmpeg")
            let args = ["-nostdin", "-loglevel", "error"] + (clip?.seek ?? []) + ["-i", media.path, "-t", String(min(10, clip.map { $0.end - $0.start } ?? 10)), "-map", "0:v:0", "-an", "-vf", "scale=-2:240", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", file.path]
        task.arguments = args
        task.standardError = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        sampleTask = task
        sampleFile = file
        playbackNote.stringValue = L("미리보기를 준비하고 있습니다…")
        task.terminationHandler = { [weak self] completed in
            DispatchQueue.main.async {
                guard let self = self, self.sampleTask === completed else { try? FileManager.default.removeItem(at: file); return }
                self.sampleTask = nil
                if completed.terminationStatus == 0, ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 2048 {
                    let player = AVPlayer(url: file)
                    player.isMuted = true
                    self.screen.player = player
                    self.playbackNote.stringValue = L("선택한 구간의 시작 부분 · 최대 10초\n무음 미리보기")
                    player.play()
                } else {
                    try? FileManager.default.removeItem(at: file)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { attempt() }
                }
            }
        }
        do { try task.run() } catch { clearSample(); playbackNote.stringValue = L("미리보기를 시작하지 못했습니다.") }
        }
        attempt()
    }
    let folderLabel = NSTextField(labelWithString: "")
    let nameField = NSTextField(string: "")
    let reveal = NSButton(title: L("저장된 파일 보기"), target: nil, action: nil)
    let rangePicker = NSSegmentedControl(labels: [L("전체"), L("구간 지정")], trackingMode: .selectOne, target: nil, action: nil)
    let beginField = NSTextField(string: "")
    let endField = NSTextField(string: "")
    let inspect = NSButton(title: L("미리보기 불러오기"), target: nil, action: nil)
    let artwork = NSImageView()
    var automaticTitle = ""
    var inspectOnly = false
    var pendingInspection = false
    var lastOutput: URL?
    var destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    var favorites: [[String: String]] = []
    var folderButtons: [NSButton] = []
    @objc func changeInlineRange() {
        beginField.isEnabled = rangePicker.selectedSegment == 1
        endField.isEnabled = rangePicker.selectedSegment == 1
    }
    @objc func inspectSource() { inspectOnly = true; saveMP3(); inspectOnly = false }
    @objc func website() { NSWorkspace.shared.open(URL(string: "https://applecraft.kr")!) }
    @objc func revealOutput() {
        if let lastOutput = lastOutput { NSWorkspace.shared.activateFileViewerSelecting([lastOutput]) }
    }
    @objc func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url { destination = url; refreshFolders() }
    }
    func refreshFolders() {
        folderLabel.stringValue = destination.path
        folderLabel.toolTip = destination.path
        for (index, button) in folderButtons.enumerated() {
            if index < favorites.count {
                let item = favorites[index]
                let path = item["path"] ?? ""
                let alias = item["alias"] ?? ""
                button.title = "⠿  " + (alias.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : alias)
                button.toolTip = path
                button.state = path == destination.path ? .on : .off
            } else { button.title = L("+ 위치 추가"); button.state = .off }
        }
        UserDefaults.standard.set(favorites, forKey: "favoriteFolders")
        UserDefaults.standard.set(destination.path, forKey: "destination")
    }
    @objc func favorite(_ sender: NSButton) {
        if sender.tag < favorites.count {
            destination = URL(fileURLWithPath: favorites[sender.tag]["path"]!)
            refreshFolders()
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                favorites.append(["path": url.path, "alias": ""])
                destination = url
                refreshFolders()
            }
        }
    }
    @objc func editFavorites() {
        guard !favorites.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = L("별명·위치 편집")
        alert.informativeText = L("별명을 비우면 실제 폴더 이름을 표시합니다.")
        let picker = NSPopUpButton()
        picker.addItems(withTitles: favorites.map { ($0["alias"]?.isEmpty == false ? $0["alias"] : URL(fileURLWithPath: $0["path"]!).lastPathComponent)! })
        let alias = NSTextField(string: "")
        alias.placeholderString = L("새 별명")
        let box = NSStackView(views: [picker, alias])
        box.orientation = .vertical; box.frame = NSRect(x: 0, y: 0, width: 300, height: 65)
        alert.accessoryView = box
        alert.addButton(withTitle: L("별명 저장")); alert.addButton(withTitle: L("등록 해제")); alert.addButton(withTitle: L("취소"))
        let result = alert.runModal()
        if result == .alertFirstButtonReturn { favorites[picker.indexOfSelectedItem]["alias"] = alias.stringValue }
        else if result == .alertSecondButtonReturn { favorites.remove(at: picker.indexOfSelectedItem) }
        refreshFolders()
    }
    var localPicker: NSView!
    var videoMode: Bool { tabs.selectedSegment == 0 }
    var clip: Clip?
    var window: NSWindow!
    let mode = NSSegmentedControl(labels: [L("내 동영상"), L("유튜브 링크")], trackingMode: .selectOne, target: nil, action: nil)
    let link = NSTextField(string: "")
    let files = NSTextField(labelWithString: L("선택한 동영상이 없습니다"))
    let captionLabel = NSTextField(labelWithString: L("자막 파일 없음 · 유튜브 모드에서는 온라인 자막 사용"))
    let status = NSTextField(wrappingLabelWithString: L("동영상이나 유튜브 링크를 선택하세요."))
    let quality = NSPopUpButton()
    let language = NSPopUpButton()
    let captions = NSButton(checkboxWithTitle: L("자막도 저장 (SRT + MP3 플레이어용 LRC)"), target: nil, action: nil)
    let choose = NSButton(title: L("동영상 선택…"), target: nil, action: nil)
    let chooseCaption = NSButton(title: L("자막 파일 선택…"), target: nil, action: nil)
    let clearCaption = NSButton(title: L("자막 해제"), target: nil, action: nil)
    let convert = PrimaryButton(title: L("오디오 추출하기 · MP3…"), target: nil, action: nil)
    let cancel = NSButton(title: L("취소"), target: nil, action: nil)
    let progress = NSProgressIndicator()
    let meter = NSProgressIndicator()
    var previewURL: URL?
    weak var rangeRow: NSView?
    weak var rangeHint: NSTextField?
    @objc func playPreview() {
        if let url = previewURL { NSWorkspace.shared.open(url) }
    }
    @objc func changeRange(_ picker: NSSegmentedControl) {
        let custom = picker.selectedSegment == 1
        rangeRow?.isHidden = !custom
        rangeHint?.stringValue = custom ? "저장할 시작·종료 시간을 입력하세요." : "구간을 지정하지 않으면 영상 전체를 저장합니다."
    }
    var source: URL?
    var captionSource: URL?
    var process: Process?
    var cancelled = false
    var busy = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildInterface()
        scheduleUpdateChecks()
    }
    private var aboutWindow: NSWindow?
    func closeAbout() {aboutWindow?.close();aboutWindow=nil}
    @objc func showAbout() {
        if let aboutWindow = aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 322),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = T("About MediaKeep","MediaKeep에 관하여")
        panel.isReleasedWhenClosed = false
        let body = panel.contentView!
        func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, top: CGFloat,
                   secondary: Bool = false, left: CGFloat? = nil) {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = secondary ? .secondaryLabelColor : .labelColor
            field.alignment = left == nil ? .center : .left
            let height = ceil(field.fittingSize.height)
            field.frame = NSRect(x: left ?? 0, y: 322 - top - height,
                                 width: left == nil ? 440 : 115, height: height)
            body.addSubview(field)
        }
        label("MediaKeep", 30, .bold, top: 20)
        label("MediaKeep", 17, .medium, top: 68)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        label(L("버전 ") + version, 13, .medium, top: 103, secondary: true)
        let divider = NSBox(frame: NSRect(x: 26, y: 175, width: 388, height: 1))
        divider.boxType = .separator
        body.addSubview(divider)
        let symbol = NSImageView(frame: NSRect(x: 162, y: 117, width: 28, height: 32))
        if let url = Bundle.main.url(forResource: "AppleCraftSymbol", withExtension: "png") {
            symbol.image = NSImage(contentsOf: url)
        }
        symbol.imageScaling = .scaleProportionallyUpOrDown
        body.addSubview(symbol)
        label(L("사과공방"), 15, .semibold, top: 168, left: 194)
        label("Apple Craft", 11, .medium, top: 190, secondary: true, left: 194)
        let homepage = NSButton(title: "applecraft.kr ↗", target: self, action: #selector(website))
        homepage.isBordered = false
        homepage.contentTintColor = .linkColor
        homepage.frame = NSRect(x: 145, y: 100, width: 150, height: 20)
        body.addSubview(homepage)
        label(L("개발자 최귀동"), 12, .medium, top: 226)
        label(L("개발일 2026년 11월"), 11, .regular, top: 247, secondary: true)
        label("© 2026 Apple Craft. All rights reserved.", 12, .medium, top: 281, secondary: true)
        aboutWindow = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { stop(); return .terminateNow }
    @objc func changeTab() {
        for view in audioCards { view.isHidden = videoMode }
        videoCard.isHidden = !videoMode
        playbackCard.isHidden = false
        if !videoMode { screen.player?.pause() }
        convert.title = videoMode ? L("동영상 다운로드 · MP4…") : L("오디오 추출하기 · MP3…")
        status.stringValue = videoMode ? L("다운로드할 유튜브 동영상 링크를 입력하세요.") : L("동영상이나 유튜브 링크를 선택하세요.")
    }
    @objc func changeMode() { choose.isEnabled = mode.selectedSegment == 0; link.isEnabled = mode.selectedSegment == 1; link.isHidden = !link.isEnabled; localPicker.isHidden = link.isEnabled }
    @objc func selectFile() {
        let p = NSOpenPanel(); p.canChooseDirectories = false
        if p.runModal() == .OK, let url = p.url { source = url; files.stringValue = url.lastPathComponent }
    }
    @objc func selectCaption() {
        let p = NSOpenPanel(); p.canChooseDirectories = false
        p.allowedContentTypes = ["srt", "vtt", "ass", "ssa"].compactMap { UTType(filenameExtension: $0) }
        if p.runModal() == .OK, let url = p.url { captionSource = url; captions.state = .on; captionLabel.stringValue = url.lastPathComponent }
    }
    @objc func resetCaption() { captionSource = nil; captionLabel.stringValue = L("자막 파일 없음 · 유튜브 모드에서는 온라인 자막 사용") }
    @objc func stop() { clearSample(); cancelled = true; if let task = process, task.isRunning { task.terminate() } }
    func report(_ text: String) { DispatchQueue.main.async { self.meter.isHidden = true; self.status.stringValue = text } }
    @discardableResult func run(_ executable: URL, _ args: [String]) throws -> String {
        let task = Process(); task.executableURL = executable; task.arguments = args
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
        try DispatchQueue.main.sync {
            if self.cancelled { throw NSError(domain: "convert", code: -1, userInfo: [NSLocalizedDescriptionKey: L("취소했습니다.")]) }
            self.process = task; try task.run()
        }
        var data = Data()
        var pending = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > 65536 { data = Data(data.suffix(65536)) }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                let line = String(decoding: pending[..<newline], as: UTF8.self)
                pending.removeSubrange(...newline)
                if line.hasPrefix("TRANSFER|") {
                    let parts = line.components(separatedBy: "|")
                    if parts.count == 4 {
                        let audio = parts[1] == "none"
                        let percent = Double(parts[2].trimmingCharacters(in: CharacterSet(charactersIn: " %")))
                        let eta = ["NA", "Unknown"].contains(parts[3]) ? "" : L(" · 남은 시간 ") + parts[3]
                        DispatchQueue.main.async {
                            self.meter.isHidden = percent == nil
                            self.meter.doubleValue = percent ?? 0
                            let done = percent.map { String(format: "%.1f%%", $0) } ?? L("계산 중")
                            self.status.stringValue = (audio ? L("음성") : L("영상")) + L(" 다운로드  ") + done + eta
                        }
                    }
                }
                if line.hasPrefix("[Merger]") { report(L("영상과 소리를 합치는 중…")) }
            }
        }
        task.waitUntilExit()
        DispatchQueue.main.sync { self.process = nil }
        if task.terminationStatus != 0 {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "convert", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(detail.suffix(1500))])
        }
        return String(decoding: data, as: UTF8.self)
    }
    func setBusy(_ value: Bool) {
        meter.isHidden = true
        busy = value
        for c: NSControl in [inspect, nameField, beginField, endField, rangePicker, tabs, videoLink, resolution, videoAudio, audioTrack, appLanguage, appearancePicker, settingsButton, videoSubs, videoLanguage, mode, link, choose, chooseCaption, clearCaption, quality, language, captions, convert] { c.isEnabled = !value }
        if !value { changeMode(); changeInlineRange() }; folderButtons.forEach { $0.isEnabled = !value }
        cancel.isHidden = !value
        convert.frame.size.width = value ? 354 : 474
        if value { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }
    @objc func saveMP3() {
        guard !busy else { return }
        pendingInspection = inspectOnly
        let online = videoMode || mode.selectedSegment == 1
        var normalizedLink = ""
        if online {
            let pasted = (videoMode ? videoLink : link).stringValue
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector?.matches(in: pasted, range: NSRange(pasted.startIndex..., in: pasted)) ?? []
            let hosts = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"]
            guard let url = matches.compactMap({ $0.url }).first(where: {
                ["http", "https"].contains($0.scheme?.lowercased() ?? "") && hosts.contains($0.host?.lowercased() ?? "")
            }) else { status.stringValue = L("올바른 유튜브 동영상 링크를 입력하세요."); return }
            normalizedLink = url.absoluteString
            let tools = ["yt-dlp", "deno", "ffmpeg"]
            guard let resources = Bundle.main.resourceURL, tools.allSatisfy({ FileManager.default.isExecutableFile(atPath: resources.appendingPathComponent($0).path) }) else {
                status.stringValue = L("다운로드 도구를 찾을 수 없습니다. 앱을 종료하고 응용 프로그램에 설치한 담아컷을 다시 열어 주세요.")
                return
            }
        } else if source == nil { status.stringValue = L("동영상 파일을 먼저 선택하세요."); return }
        let urlText = normalizedLink
        if online {
            let resources = Bundle.main.resourceURL!
            cancelled = false
            setBusy(true)
            status.stringValue = L("영상 제목을 확인하고 있습니다…")
            DispatchQueue.global(qos: .userInitiated).async {
                let metadataBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let titleFile = metadataBase.appendingPathExtension("info.json")
                defer { try? FileManager.default.removeItem(at: titleFile) }
                do {
                    try self.run(resources.appendingPathComponent("yt-dlp"), ["--ignore-config", "--no-playlist", "--skip-download", "--socket-timeout", "20", "--js-runtimes", "deno:" + resources.appendingPathComponent("deno").path, "--ignore-no-formats-error", "--ffmpeg-location", resources.path, "--write-info-json", "-o", "infojson:" + metadataBase.path, "--", urlText])
                    let info = try JSONSerialization.jsonObject(with: Data(contentsOf: titleFile)) as? [String: Any] ?? [:]
                    let raw = info["title"] as? String ?? "YouTube"
                    let heights = Set((info["formats"] as? [[String: Any]] ?? []).compactMap { $0["height"] as? Int }).sorted()
                    let duration = info["duration"] as? Double ?? 0
                    let subs = info["subtitles"] as? [String: Any] ?? [:]
                    let auto = info["automatic_captions"] as? [String: Any] ?? [:]
                    var languages: [String] = []
                    for language in supportedLanguages {
                        let name = language.name
                        var kind = L(" 없음")
                        if language.subtitleAliases.contains(where: {subs[$0] != nil}) { kind = L(" 제공") }
                        else if language.subtitleAliases.contains(where: {auto[$0] != nil || auto[$0+"-orig"] != nil}) { kind = L(" 자동") }
                        languages.append(name + kind)
                    }
                    let details = heights.map { "\($0)p" }.joined(separator: " · ") + L("\n자막  ") + languages.joined(separator: " · ")
                    var thumbnail: NSImage?
                    if let path = info["thumbnail"] as? String, let url = URL(string: path), let data = try? Data(contentsOf: url) { thumbnail = NSImage(data: data) }
                    let picture = thumbnail
                    let clean = raw.components(separatedBy: CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))).filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                    var name = ""
                    for character in clean {
                        if name.utf8.count + String(character).utf8.count > 230 { break }
                        name.append(character)
                    }
                    let title = name.isEmpty ? "YouTube" : name
                    DispatchQueue.main.async {
                        self.setBusy(false)
                        if !self.cancelled { self.preview(true, urlText, title, duration, details, picture) }
                        else { self.status.stringValue = L("취소했습니다.") }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.setBusy(false)
                        self.status.stringValue = self.cancelled ? L("취소했습니다.") : L("영상 제목 조회 실패 · ") + error.localizedDescription
                    }
                }
            }
        } else { preview(false, urlText, source!.deletingPathExtension().lastPathComponent, 0, "", nil) }
    }
    func preview(_ online: Bool, _ link: String, _ title: String, _ duration: Double, _ details: String, _ picture: NSImage?) {
        previewURL = online ? URL(string: link) : source
        if nameField.stringValue.isEmpty || nameField.stringValue == automaticTitle { nameField.stringValue = title }
        automaticTitle = title
        playbackNote.stringValue = title + "\n" + details
        artwork.image = picture
        artwork.isHidden = picture == nil
        screen.isHidden = picture != nil
        if !online, let source = source { screen.player = AVPlayer(url: source) }
        if pendingInspection { return }
        selectDestination(online, link, title)
    }
    func downloadVideo(_ link: String, to output: URL) {
        let resources = Bundle.main.resourceURL!
        let height = [2160, 1080, 720, 480][resolution.indexOfSelectedItem]
        let clip = self.clip
        let wantSubs = videoSubs.state == .on
        let lang = subtitleCode(videoLanguage)
        let audioChoice = audioPreference(videoAudio)
        let subtitle = output.deletingPathExtension().appendingPathExtension("srt")
        if wantSubs && FileManager.default.fileExists(atPath: subtitle.path) {
            let alert = NSAlert()
            alert.messageText = subtitle.lastPathComponent + L(" 자막을 덮어쓸까요?")
            alert.addButton(withTitle: L("덮어쓰기"))
            alert.addButton(withTitle: L("취소"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        cancelled = false
        setBusy(true)
        status.stringValue = L("영상과 소리를 다운로드하고 있습니다…")
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let folder = output.deletingLastPathComponent().appendingPathComponent(".video-" + UUID().uuidString)
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: false)
                defer { try? fm.removeItem(at: folder) }
                DispatchQueue.main.async { self.startSample(in: folder, clip: clip) }
                let common = ["--ignore-config", "--no-playlist", "--newline", "--progress", "--progress-delta", "1", "--progress-template", "download:TRANSFER|%(info.vcodec)s|%(progress._percent_str)s|%(progress._eta_str)s", "--socket-timeout", "20", "--retries", "2", "--js-runtimes", "deno:" + resources.appendingPathComponent("deno").path, "--ffmpeg-location", resources.path]
                let format = videoFormat(height: height, language: audioChoice)
                let downloader = resources.appendingPathComponent("yt-dlp")
                let target = folder.appendingPathComponent("result.%(ext)s").path
                do {
                    try self.run(downloader, common + ["-S", "res,vcodec:h264", "-f", format, "--merge-output-format", "mp4", "-o", target, "--", link])
                } catch {
                    let detail = error.localizedDescription.lowercased()
                    guard !DispatchQueue.main.sync(execute: { self.cancelled }),
                          ["403", "requested format", "fragment", "unable to download video data"].contains(where: detail.contains) else { throw error }
                    self.report(L("선택한 스트림을 받을 수 없어 호환 MP4로 다시 시도합니다…"))
                    try self.run(downloader, common + ["-f", videoFormat(height: height, language: audioChoice, compatible: true), "-o", target, "--", link])
                }
                var message = L("저장 완료 · ") + output.lastPathComponent
                var stagedSubtitle: URL?
                if wantSubs {
                    self.report(L("선택한 언어의 자막을 확인하고 있습니다…"))
                    do {
                        try self.run(resources.appendingPathComponent("yt-dlp"), common + ["--skip-download", "--write-subs", "--write-auto-subs", "--sub-langs", subtitleLanguages(lang), "--sub-format", "vtt", "-o", folder.appendingPathComponent("caption.%(ext)s").path, "--", link])
                        let tracks = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                        if let track = tracks.first(where: { $0.lastPathComponent == "caption." + lang + ".vtt" }) ?? tracks.first(where: { $0.pathExtension == "vtt" }) {
                            let srt = folder.appendingPathComponent("result.srt")
                            try self.run(resources.appendingPathComponent("ffmpeg"), ["-nostdin", "-loglevel", "error", "-i", track.path, "-map", "0:s:0", "-c:s", "srt", srt.path])
                            try clip?.align(srt)
                            guard (try String(contentsOf: srt, encoding: .utf8)).contains("-->") else { throw NSError(domain: "caption", code: 1) }
                            stagedSubtitle = srt
                        } else { message = L("MP4 저장 완료 · 선택한 언어의 자막이 없습니다.") }
                    } catch { message = L("MP4 저장 완료 · 자막을 가져오지 못했습니다.") }
                }
                var movie = folder.appendingPathComponent("result.mp4")
                let ff = resources.appendingPathComponent("ffmpeg")
                if let clip = clip {
                    self.report(L("선택한 구간을 MP4로 변환하는 중…"))
                    let cut = folder.appendingPathComponent("clip.mp4")
                    try self.run(ff, ["-nostdin", "-loglevel", "error"] + clip.seek + ["-i", movie.path] + clip.limit + ["-map","0:v:0","-map","0:a:0","-c:v","libx264","-preset","veryfast","-c:a","aac",cut.path])
                    movie = cut
                }
                if let srt = stagedSubtitle {
                    self.report(L("MP4에 선택형 자막을 넣는 중…"))
                    let muxed = folder.appendingPathComponent("subtitled.mp4")
                    do { try self.run(ff, ["-nostdin","-loglevel","error","-i",movie.path,"-i",srt.path,"-map","0:v:0","-map","0:a:0","-map","1:s:0","-c","copy","-c:s","mov_text","-metadata:s:s:0","language=" + languageInfo(lang).iso639,"-disposition:s:0","0",muxed.path])
                    movie = muxed
                    } catch { message = L("MP4 저장 완료 · 자막은 SRT 파일로 저장했습니다.") }
                }
                guard !DispatchQueue.main.sync(execute: { self.cancelled }) else { throw CancellationError() }
                if fm.fileExists(atPath: output.path) { _ = try fm.replaceItemAt(output, withItemAt: movie) }
                else { try fm.moveItem(at: movie, to: output) }
                if let srt = stagedSubtitle {
                    do {
                        if fm.fileExists(atPath: subtitle.path) { _ = try fm.replaceItemAt(subtitle, withItemAt: srt) }
                        else { try fm.moveItem(at: srt, to: subtitle) }
                        if movie.lastPathComponent == "subtitled.mp4" { message = L("MP4와 SRT 자막을 함께 저장했습니다.") }
                    } catch { message = L("MP4 저장 완료 · 자막 파일 저장에 실패했습니다.") }
                }
                let finishedMessage = message
                DispatchQueue.main.async {
                    self.setBusy(false)
                    self.clearSample()
                    self.screen.player = AVPlayer(url: output)
                    self.playbackNote.stringValue = L("저장 완료 · 재생 버튼을 눌러 결과를 확인하세요.")
                    self.status.stringValue = finishedMessage
                    self.lastOutput = output; self.reveal.isEnabled = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.setBusy(false)
                    self.clearSample()
                    self.playbackNote.stringValue = L("다운로드를 시작하면 여기에 영상이 표시됩니다.")
                    self.status.stringValue = self.cancelled ? L("취소했습니다.") : L("영상 저장 실패 · ") + error.localizedDescription
                }
            }
        }
    }
    func selectDestination(_ online: Bool, _ urlText: String, _ title: String) {
        clip = nil
        if rangePicker.selectedSegment == 1 {
            guard let start = Clip.seconds(beginField.stringValue.isEmpty ? "0" : beginField.stringValue),
                  let end = Clip.seconds(endField.stringValue), end > start else {
                status.stringValue = L("시작과 종료 시간을 확인하세요."); return
            }
            clip = Clip(start: start, end: end)
        }
        let rawName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = (rawName.isEmpty ? title : rawName).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !filename.isEmpty, !filename.hasPrefix("."), filename.utf8.count < 235 else {
            status.stringValue = L("파일 이름을 짧게 입력하세요."); return
        }
        let suffix = videoMode ? "mp4" : "mp3"
        let baseName = filename.lowercased().hasSuffix("." + suffix) ? String(filename.dropLast(suffix.count + 1)) : filename
        let output = destination.appendingPathComponent(baseName).appendingPathExtension(suffix)
        guard FileManager.default.isWritableFile(atPath: destination.path) else {
            status.stringValue = L("저장 폴더에 쓸 수 없습니다. 다른 위치를 선택하세요."); return
        }
        if FileManager.default.fileExists(atPath: output.path) {
            let alert = NSAlert(); alert.messageText = L("같은 이름의 파일을 덮어쓸까요?")
            alert.addButton(withTitle: L("덮어쓰기")); alert.addButton(withTitle: L("취소"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        screen.isHidden = false; artwork.isHidden = true
        if videoMode { downloadVideo(urlText, to: output); return }
        let srtOut = output.deletingPathExtension().appendingPathExtension("srt")
        let lrcOut = output.deletingPathExtension().appendingPathExtension("lrc")
        let input = source; let selectedCaption = captionSource; let wantCaptions = captions.state == .on
        let protected = [online ? nil : input, wantCaptions ? selectedCaption : nil].compactMap { $0?.standardizedFileURL }
        if (wantCaptions ? [output, srtOut, lrcOut] : [output]).contains(where: { protected.contains($0.standardizedFileURL) }) { status.stringValue = L("원본 파일과 다른 이름으로 저장하세요."); return }
        if wantCaptions && [srtOut, lrcOut].contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            let alert = NSAlert(); alert.messageText = L("같은 이름의 자막을 덮어쓸까요?"); alert.informativeText = "\(srtOut.lastPathComponent), \(lrcOut.lastPathComponent)"; alert.addButton(withTitle: L("덮어쓰기")); alert.addButton(withTitle: L("취소"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let clip = self.clip
        let bitrate = ["320k", "192k", "128k"][quality.indexOfSelectedItem]
        let lang = subtitleCode(language)
        let audioChoice = audioPreference(audioTrack)
        let resources = Bundle.main.resourceURL!
        let ffmpeg = resources.appendingPathComponent("ffmpeg")
        let yt = resources.appendingPathComponent("yt-dlp")
        let deno = resources.appendingPathComponent("deno")
        cancelled = false; setBusy(true); status.stringValue = L("준비하고 있습니다…")
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let work = output.deletingLastPathComponent().appendingPathComponent(".mp3-" + UUID().uuidString, isDirectory: true)
            var result = ""; var saved = false
            do {
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: work) }
                let base = ["--ignore-config", "--no-playlist", "--newline", "--progress", "--progress-delta", "1", "--progress-template", "download:TRANSFER|%(info.vcodec)s|%(progress._percent_str)s|%(progress._eta_str)s", "--socket-timeout", "20", "--retries", "2", "--js-runtimes", "deno:" + deno.path]
                var media = input ?? work.appendingPathComponent("pending")
                if online {
                    self.report(L("유튜브에서 오디오를 다운로드하고 있습니다…"))
                    try self.run(yt, base + ["-f", audioFormat(language: audioChoice), "-o", work.appendingPathComponent("audio.%(ext)s").path, "--", urlText])
                    guard let downloaded = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first(where: { $0.lastPathComponent.hasPrefix("audio.") && !$0.path.hasSuffix(".part") }) else { throw NSError(domain: "convert", code: 1, userInfo: [NSLocalizedDescriptionKey: L("다운로드한 오디오를 찾을 수 없습니다.")]) }
                    media = downloaded
                }
                self.report(L("MP3로 변환하고 있습니다…"))
                let mp3 = work.appendingPathComponent("result.mp3")
                try self.run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-nostdin", "-y"] + (clip?.seek ?? []) + ["-i", media.path] + (clip?.limit ?? []) + ["-map", "0:a:0", "-vn", "-c:a", "libmp3lame", "-b:a", bitrate, mp3.path])
                var caption = selectedCaption
                var captionNote = ""
                if wantCaptions && caption == nil && online {
                    self.report(L("유튜브 자막을 가져오고 있습니다…"))
                    do {
                        try self.run(yt, base + ["--skip-download", "--write-subs", "--write-auto-subs", "--sub-langs", subtitleLanguages(lang), "--sub-format", "vtt/best", "-o", work.appendingPathComponent("captions.%(ext)s").path, "--", urlText])
                        caption = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).filter { ["vtt", "srt", "ass", "ssa"].contains($0.pathExtension) }.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
                        if caption == nil { captionNote = L(" · 선택한 언어의 자막이 없어 MP3만 저장했습니다.") }
                    } catch { captionNote = L(" · 온라인 자막을 가져오지 못해 MP3만 저장했습니다.") }
                }
                let srt = work.appendingPathComponent("result.srt")
                let lrc = work.appendingPathComponent("result.lrc")
                var hasCaption = false
                if wantCaptions, let caption = caption {
                    self.report(L("SRT와 LRC 자막을 생성하고 있습니다…"))
                    do {
                        try self.run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", caption.path, "-map", "0:s:0", "-c:s", "srt", srt.path])
                        try clip?.align(srt)
                        let text = try String(contentsOf: srt, encoding: .utf8)
                        let lyrics = lrcFromSRT(text)
                        guard !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NSError(domain: "caption", code: 1) }
                        try lyrics.write(to: lrc, atomically: true, encoding: .utf8); hasCaption = true
                    } catch { captionNote = L(" · 자막 파일을 변환하지 못해 MP3만 저장했습니다.") }
                } else if wantCaptions && !online { captionNote = L(" · 선택한 자막이 없어 MP3만 저장했습니다.") }
                let isCancelled = DispatchQueue.main.sync { self.cancelled }
                if isCancelled { throw NSError(domain: "convert", code: -1) }
                func install(_ from: URL, _ to: URL) throws {
                    if fm.fileExists(atPath: to.path) { _ = try fm.replaceItemAt(to, withItemAt: from) }
                    else { try fm.moveItem(at: from, to: to) }
                }
                try install(mp3, output); saved = true
                if hasCaption { try install(srt, srtOut); try install(lrc, lrcOut) }
                result = hasCaption ? L("완료! MP3 + SRT + LRC를 저장했습니다.") : L("완료! MP3를 저장했습니다.") + captionNote
            } catch {
                let stopped = DispatchQueue.main.sync { self.cancelled }
                result = stopped ? L("취소했습니다.") : (saved ? L("MP3는 저장했으나 자막 저장에 실패했습니다: ") : L("작업 실패: ")) + error.localizedDescription
            }
            let finalResult = result; let finalSaved = saved
            DispatchQueue.main.async {
                self.setBusy(false); self.status.stringValue = finalResult
                if finalSaved { self.lastOutput = output; self.reveal.isEnabled = true }
            }
        }
    }
}
if CommandLine.arguments.contains("--ui-test") {
    renderInterfaceTests()
} else if CommandLine.arguments.contains("--integration-test") {
    try testLocalConversion()
} else if CommandLine.arguments.contains("--self-test") {
    testUpdates()

    let input = "1\n00:00:01,250 --> 00:00:03,000\n안녕하세요\n두 번째 줄\n\n2\n01:02:03,456 --> 01:02:04,000\n<b>테스트</b>\n"
    precondition(lrcFromSRT(input) == "[00:01.25]안녕하세요 두 번째 줄\n[62:03.45]테스트\n")
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try input.write(to: fixture, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fixture) }
    try Clip(start: 2, end: 2.75).align(fixture)
    let shifted = try String(contentsOf: fixture, encoding: .utf8)
    precondition(shifted.contains("00:00:00,000 --> 00:00:00,750") && !shifted.contains("테스트"))
    print("PASS: subtitle intersection and time shift")
    print("PASS: SRT → LRC timestamps, Korean, multiline, tags")
} else {
    let app = NSApplication.shared; let delegate = App(); app.delegate = delegate
    app.setActivationPolicy(.regular); withExtendedLifetime(delegate) { app.run() }
}
