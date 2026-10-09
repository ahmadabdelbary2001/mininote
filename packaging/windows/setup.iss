; Inno Setup Script for MiniNote Windows Installer
[Setup]
AppId={{D3EFA101-7290-4821-9876-FA4888123456}
AppName=MiniNote
AppVersion=1.0.4
AppPublisher=Ahmad Abdelbary
AppPublisherURL=https://github.com/ahmadabdelbary2001/mininote
DefaultDirName={autopf}\MiniNote
DefaultGroupName=MiniNote
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=mininote-windows-x64-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\flutter_app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\MiniNote"; Filename: "{app}\mininote.exe"
Name: "{autodesktop}\MiniNote"; Filename: "{app}\mininote.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\mininote.exe"; Description: "{cm:LaunchProgram,MiniNote}"; Flags: nowait postinstall skipifsilent
