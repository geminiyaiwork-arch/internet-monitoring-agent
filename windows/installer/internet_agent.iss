; Internet Monitoring Agent — klassik Windows Setup (.exe)
;
; Oldin: flutter build windows
; Keyin: Inno Setup 6 o‘rnating, ushbu faylni ochib Compile (yoki ISCC bilan).
;
; Fayl joyi: windows/installer/internet_agent.iss

#define MyAppName "Internet Monitoring Agent"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "E-MMTB"
#define MyAppExeName "internet.exe"
; .iss faylidan loyiha ildizigacha
#define BuildOutput "..\\..\\build\\windows\\x64\\runner\\Release"

[Setup]
AppId={{C8F4A1E2-9D3B-5F6A-8C7E-1B2D3E4F5A6B}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://e-mmtb.uz
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=InternetMonitoringAgent_Setup_{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildOutput}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
