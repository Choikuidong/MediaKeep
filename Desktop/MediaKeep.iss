#ifndef MediaKeepVersion
  #define MediaKeepVersion "1.0.0"
#endif

#ifdef MediaKeepARM64
  #define Product "MediaKeep (ARM64)"
  #define AppKey "AppleCraft.MediaKeep.ARM64"
  #define Architecture "arm64"
  #define MinimumWindows "10.0.22000"
  #define SetupName "MediaKeep-" + MediaKeepVersion + "-Windows-ARM64-Setup"
#else
  #define Product "MediaKeep"
  #define AppKey "AppleCraft.MediaKeep"
  #define Architecture "x64compatible"
  #define MinimumWindows "10.0"
  #define SetupName "MediaKeep-" + MediaKeepVersion + "-Windows-x64-Setup"
  #if MediaKeepVersion == "1.0.0"
    #undef SetupName
    #define SetupName "MediaKeep-1.0.0-Windows-x64-Setup-r2"
  #endif
#endif

[Setup]
AppId={#AppKey}
AppName={#Product}
AppVersion={#MediaKeepVersion}
AppPublisher=Apple Craft
AppPublisherURL=https://applecraft.kr/
DefaultDirName={localappdata}\Programs\{#Product}
PrivilegesRequired=lowest
ArchitecturesAllowed={#Architecture}
ArchitecturesInstallIn64BitMode={#Architecture}
MinVersion={#MinimumWindows}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\MediaKeep.exe
OutputDir=..\build
OutputBaseFilename={#SetupName}
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\installer-input\MediaKeep\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\{#Product}"; Filename: "{app}\MediaKeep.exe"
Name: "{userdesktop}\{#Product}"; Filename: "{app}\MediaKeep.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\MediaKeep.exe"; Description: "Launch MediaKeep"; Flags: nowait postinstall skipifsilent
