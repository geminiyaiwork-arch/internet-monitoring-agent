; Internet Monitoring Agent — klassik Windows Setup (.exe)
;
; Build:
;   flutter build windows --release
;   choco install innosetup -y   (yoki qo'lda o'rnatib qo'ying)
;   ISCC windows/installer/internet_agent.iss
;
; Natija: build/installer/InternetMonitoringAgent_Setup_<ver>.exe

#define MyAppName "Internet Monitoring Agent"
#define MyAppVersion "1.1.4"
#define MyAppPublisher "E-MMTB"
#define MyAppExeName "internet.exe"
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
Name: "startupicon"; Description: "Kompyuter yonganda avtomatik ishga tushirish"; GroupDescription: "Autostart:"; Flags: checkedonce

[Files]
Source: "{#BuildOutput}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; VC++ 2015-2022 Redistributable (MSVCP140.dll va shu kabilar). Yuklanadi va run da o'rnatiladi.
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: VCRedistNeedsInstall

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--startup-tray"; Tasks: startupicon

[Run]
; Avval VC++ Redistributable o'rnatish (kerak bo'lsa)
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Microsoft VC++ Runtime o'rnatilmoqda..."; Check: VCRedistNeedsInstall; Flags: waituntilterminated
; Keyin asosiy dasturni ishga tushirish
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
function VCRedistNeedsInstall: Boolean;
var
  Version: string;
begin
  // MSVCP140.dll versiyasini tekshirish (VC++ 2015-2022 bir oilada).
  if RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Version', Version) then
  begin
    // Versiya bor — o'rnatish kerakmas
    Result := False;
  end
  else
    Result := True;
end;
