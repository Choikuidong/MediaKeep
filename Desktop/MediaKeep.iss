[Setup]
AppId=AppleCraft.MediaKeep
AppName=MediaKeep
AppVersion=1.0.0
AppPublisher=Apple Craft
AppPublisherURL=https://applecraft.kr/
DefaultDirName={localappdata}\Programs\MediaKeep
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\MediaKeep.exe
OutputDir=..\build
OutputBaseFilename=MediaKeep-1.0.0-Windows-x64-Setup-r2
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\installer-input\MediaKeep\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\MediaKeep"; Filename: "{app}\MediaKeep.exe"
Name: "{userdesktop}\MediaKeep"; Filename: "{app}\MediaKeep.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\MediaKeep.exe"; Description: "Launch MediaKeep"; Flags: nowait postinstall skipifsilent
