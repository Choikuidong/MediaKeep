# MediaKeep 1.0.0 — user guide

[한국어 설명](../README.md) · [Downloads](https://github.com/Choikuidong/MediaKeep/releases/latest) · [Apple Craft](https://applecraft.kr)

**Save videos. Extract audio. Keep the parts you want.**

MediaKeep is a free desktop utility for downloading permitted YouTube videos, extracting MP3 audio, and keeping subtitles alongside your media. It runs as a native AppKit app on Apple Silicon Macs and a Qt desktop app on Windows and Linux.

## Choose your download

| Platform | File | Start here |
|---|---|---|
| macOS 13+, Apple Silicon | `MediaKeep-1.0.0-macOS-arm64.dmg` | Open the DMG; drag the app into Applications |
| Windows 10/11, x64 | `MediaKeep-1.0.0-Windows-x64.zip` | Extract everything; open `MediaKeep.exe` inside the folder |
| Linux x86-64, Ubuntu 22.04+ baseline | `MediaKeep-1.0.0-Linux-x86_64.tar.gz` | Extract; run `./MediaKeep/MediaKeep` in a desktop session |

Keep the Windows/Linux application folder intact, including `_internal`. These packages include the media tools; Python is not required to run them. The Mac build is locally signed without Developer ID notarization. The Windows build has no Authenticode signature. OS first-launch warnings may therefore appear.

This is a new release series. If you previously installed MediaKeep 1.2.x, install 1.0.0 manually once: its version number is lower. Subsequent stable 1.x updates can be checked from the new app.

## A quick first download

1. Select **Video Download**.
2. Paste a single YouTube video link you are permitted to download.
3. Select **Load preview** to see the title and source thumbnail. **Preview original** opens the source page in your browser.
4. Choose your quality. **4K / 2160p** is the default ceiling, not an upscaling option.
5. Turn subtitles on or off; choose a subtitle and audio language if needed.
6. Leave **Entire video** enabled to save everything. For a range, enter times such as `01:20` and `02:45`.
7. Choose the destination folder before starting. Review the file name; the video title is suggested automatically.
8. Select **Download MP4**. Progress is shown as a percentage; you may cancel while processing.
9. Use **Reveal saved file** after completion. Linux opens the containing folder; Windows selects the file in Explorer.

## Extract MP3 audio

Select **Audio Extraction**, then choose a local video or paste a YouTube link. Pick 320, 192, or 128 kbps. The default is 192 kbps. An optional subtitle file can be selected for local media. **Extract MP3** saves MP3 and, when available and selected, SRT and LRC files.

SRT is a normal subtitle file. LRC is a timestamped lyric format supported by some audio players. A custom range shifts subtitle timestamps to start at the beginning of the saved clip.

## Languages and dubbing

The interface supports 20 languages. English is the default. Change the language using the upper-right selector; your choice is saved locally.

**App language** makes subtitle selection follow the interface language. Audio also offers the app language, original audio, and individual language choices. MediaKeep prefers an existing matching dub; it falls back to original-marked audio and then available audio when no matching dub exists.

MediaKeep does **not** create AI translations or voice dubbing. It downloads subtitles/audio actually supplied by the source service. Subtitle availability and automated-caption quality vary. An unavailable subtitle does not imply that downloading a video grants translation or redistribution rights.

Supported languages: English, Korean, Japanese, Simplified Chinese, Traditional Chinese, Spanish, French, German, Portuguese (Brazil), Italian, Russian, Indonesian, Dutch, Polish, Turkish, Ukrainian, Vietnamese, Swedish, Czech, and Romanian.

Source titles, custom folder names, OS dialogs, external-tool diagnostics, and release notes are not automatically translated.

## Save locations

Register up to nine folders using **+ Add location**. Folder pickers allow creating new folders. Click a shortcut to select it. **Edit names** changes the nickname; leaving it empty restores the real folder name. Removing a shortcut never deletes its folder. Drag the grip to reorder shortcuts.

## Appearance and preview

**Settings → Appearance** offers Midnight Blue, Warm Amber, Soft Light, and Forest Green. Soft Light is the default.

Source previews are not promises about a download's completion. On Mac, a short muted video sample may be prepared from incoming data. Windows/Linux show source thumbnails and progress, then play the completed local media. Browser previews open the original source page. Range downloads may fetch the full source before cutting, so their network usage is not limited to the selected duration.

## Updating

The app checks stable GitHub Releases at launch and daily while it is running. You can check immediately from the menu. A newer release offers Download Update, Later, or Skip This Version. Only a higher numeric stable release with an uploaded installer for your platform is offered. Editing source files alone does not notify users. After downloading, quit and replace the app yourself; no background service or silent installer is installed.

## Troubleshooting

- **No 4K output:** the source must actually provide that resolution. MediaKeep uses an available resolution at or below the selected maximum.
- **Original language instead of a dub:** no matching dubbed track may be available.
- **Missing subtitles:** select a source-provided language. Optional MP4 subtitles may need enabling in your player. Look for the separate SRT too.
- **Download errors:** check the link and network. DRM and private/paid/account/region/age restrictions are not bypassed. Source services can change; check for an app update.
- **Linux will not start:** use a desktop session and install Qt's system display/audio libraries. On Ubuntu, see the commands in the main README. Some languages may require appropriate system fonts.
- **Windows will not start:** extract all files; do not run only the EXE copied away from `_internal`.

## Privacy, permissions, and credits

Preferences are saved on your computer. Downloads contact the original service; update checks contact GitHub. MediaKeep has no separate account requirement, cloud synchronization, or app analytics server.

Download or convert only content you have permission to use. Check applicable law, source terms, and the rights holder's permission. You are responsible for your use.

Developed by **Choi Kuidong / 최귀동**, **Apple Craft / 사과공방**. Third-party notices are included in `Licenses`. See the main README for the build process and source layout.

© 2026 Apple Craft. All rights reserved.
