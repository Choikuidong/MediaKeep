import Cocoa

struct AppVersion: Comparable {
    let parts:[Int]
    init?(_ text:String) {
        let s=text.hasPrefix("v") ? String(text.dropFirst()):text
        let pieces=s.split(separator:".",omittingEmptySubsequences:false)
        guard (2...4).contains(pieces.count), pieces.allSatisfy({!$0.isEmpty && $0.allSatisfy(\.isNumber)}), pieces.allSatisfy({Int($0) != nil}) else{return nil}
        parts=pieces.map{Int($0)!}
    }
    static func ==(lhs:Self,rhs:Self)->Bool {!(lhs<rhs) && !(rhs<lhs)}
    static func <(lhs:Self,rhs:Self)->Bool {
        for i in 0..<max(lhs.parts.count,rhs.parts.count) {let a=i<lhs.parts.count ? lhs.parts[i]:0,b=i<rhs.parts.count ? rhs.parts[i]:0;if a != b{return a<b}}
        return false
    }
}
struct UpdateRelease:Decodable {
    struct Asset:Decodable {let name:String;let browser_download_url:URL;let size:Int;let state:String}
    let tag_name:String;let body:String?;let draft:Bool;let prerelease:Bool;let assets:[Asset]
    var download:URL? {
        assets.first {a in
            let path=a.browser_download_url.path
            return a.state=="uploaded" && a.size>0 && a.name.hasPrefix("MediaKeep-") && a.name.hasSuffix("-arm64.dmg") && a.browser_download_url.scheme=="https" && a.browser_download_url.host=="github.com" && path.hasPrefix("/Choikuidong/MediaKeep/releases/download/")
        }?.browser_download_url
    }
}
extension App {
    func scheduleUpdateChecks() {
        DispatchQueue.main.asyncAfter(deadline:.now()+3){[weak self] in self?.checkUpdate(manual:false)}
        updateTimer=Timer.scheduledTimer(withTimeInterval:3600,repeats:true){[weak self] _ in self?.checkUpdate(manual:false)}
    }
    @objc func manualUpdateCheck(){checkUpdate(manual:true)}
    func checkUpdate(manual:Bool) {
        guard !updateChecking else{return}
        let prefs=UserDefaults.standard
        if !manual {
            guard prefs.object(forKey:"automaticUpdates") as? Bool != false,!busy else{return}
            if let checked=prefs.object(forKey:"lastUpdateCheck") as? Date,Date().timeIntervalSince(checked)<86400{return}
        }
        updateChecking=true
        var request=URLRequest(url:URL(string:"https://api.github.com/repos/Choikuidong/MediaKeep/releases/latest")!);request.timeoutInterval=20
        request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept");request.setValue("MediaKeep-macOS",forHTTPHeaderField:"User-Agent")
        URLSession.shared.dataTask(with:request){[weak self] data,response,error in
            let code=(response as? HTTPURLResponse)?.statusCode ?? 0
            let release=data.flatMap{try? JSONDecoder().decode(UpdateRelease.self,from:$0)}
            DispatchQueue.main.async {
                guard let self=self else{return};self.updateChecking=false
                if code==404 {prefs.set(Date(),forKey:"lastUpdateCheck");if manual{self.updateMessage(T("No release is available yet.","아직 공개된 업데이트가 없습니다."))};return}
                guard error==nil,code==200,let release=release,!release.draft,!release.prerelease,let remote=AppVersion(release.tag_name),let current=AppVersion(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0.0") else {
                    if manual {self.updateMessage(T("Could not check for updates. Please try again later.","업데이트를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."))};return
                }
                // Retry later if a download is active, without consuming today's check.
                if self.busy {if manual{self.updateMessage(T("Check again after the current task finishes.","현재 작업이 끝난 뒤 다시 확인해 주세요."))};return}
                prefs.set(Date(),forKey:"lastUpdateCheck")
                guard remote>current else{if manual{self.updateMessage(T("MediaKeep is up to date.","최신 버전입니다."))};return}
                guard manual || prefs.string(forKey:"skippedVersion") != release.tag_name else{return}
                guard let download=release.download else{if manual{self.updateMessage(T("The new release is not ready for this Mac yet.","새 릴리스의 Mac 설치 파일이 아직 준비되지 않았습니다."))};return}
                let alert=NSAlert();alert.messageText=T("A new MediaKeep version is available","새 MediaKeep 버전이 있습니다")
                alert.informativeText=release.tag_name+"\n\n"+String((release.body ?? "").prefix(1800))
                alert.addButton(withTitle:T("Download Update","업데이트 다운로드"));alert.addButton(withTitle:T("Later","나중에"));alert.addButton(withTitle:T("Skip This Version","이 버전 건너뛰기"))
                let result=alert.runModal()
                if result == .alertFirstButtonReturn{NSWorkspace.shared.open(download)}
                if result == .alertThirdButtonReturn{prefs.set(release.tag_name,forKey:"skippedVersion")}
            }
        }.resume()
    }
    func updateMessage(_ text:String){let alert=NSAlert();alert.messageText=text;alert.addButton(withTitle:T("OK","확인"));alert.runModal()}
}
