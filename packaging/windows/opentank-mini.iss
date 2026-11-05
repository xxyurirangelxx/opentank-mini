; Instalador do OpenTank Mini para Windows.
;
; Compilar com Inno Setup 6:
;   ISCC.exe /DAppVersion=1.0.0 packaging\windows\opentank-mini.iss
;
; O script assume que `flutter build windows --release` ja rodou: ele empacota
; `app\build\windows\x64\runner\Release` inteiro (exe + DLLs + dados).
;
; Nao exige privilegios de administrador: instala por usuario em
; `%LOCALAPPDATA%\Programs\OpenTank Mini`, que e onde os apps Flutter do
; Windows costumam viver.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName        "OpenTank Mini"
#define AppPublisher   "OpenTank Mini"
#define AppExeName     "opentank_mini.exe"
#define AppId          "{{8F3C1B6E-4A2D-4E77-9C1B-0D5E7A9F2C41}"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Instalacao por usuario: sem UAC, e o Flutter nao coloca nada em pastas do
; sistema. PrivilegesRequiredOverridesAllowed permite que o usuario escolha
; "para todos" se quiser.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\dist
OutputBaseFilename=OpenTankMini-{#AppVersion}-windows-x64
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Fecha o app antes de atualizar, para nao falhar ao sobrescrever a DLL.
CloseApplications=yes
RestartApplications=no
MinVersion=10.0
LicenseFile=..\..\LICENSE

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\app\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; \
    Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Cache e arquivos gerados pelo Flutter ficam na pasta do app.
Type: filesandordirs; Name: "{app}\data"
