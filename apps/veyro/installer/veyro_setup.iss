; VEYRO - некастодиальный мультивалютный кошелёк. Первый релиз (1.0.0).
; Установщик: рабочие ярлыки (Пуск + рабочий стол), чистая деинсталляция,
; данные кошельков (%APPDATA%\veyro) НЕ трогаются при деинсталляции.
; Сборка: installer/build_installer.ps1 (генерирует /DRELEASE из pubspec).

#define MyAppName "VEYRO"
#define MyAppPublisher "VEYRO"
#ifndef RELEASE
  #define RELEASE "1.0.0"
#endif
#define MyAppVersion RELEASE
#define MyAppExeName "veyro.exe"
#define MyAppId "{{8A1E9A62-7B4D-4F32-9B0E-1B5F2C7D3E91}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Стабильный путь установки зависит от привилегий (autopf):
; per-machine -> Program Files\VEYRO; per-user -> %LOCALAPPDATA%\Programs\VEYRO.
DefaultDirName={autopf}\VEYRO
; Владелец может выбрать режим (по умолчанию - без админа, per-user).
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Только Windows 10/11.
MinVersion=10.0
OutputDir=..\build\windows\installer
OutputBaseFilename=VEYRO-setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayName={#MyAppName} {#MyAppVersion}
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
; Кошельки пользователя вне установщика: деинсталляция их не затрагивает.
Uninstallable=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Вся сборка Flutter Windows: exe + flutter_windows.dll + data\ + плагины.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Пуск -> Программы -> VEYRO (+ Deinstall)
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Comment: "{cm:LaunchComment}"
Name: "{autoprograms}\{#MyAppName}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
; Рабочий стол
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Comment: "{cm:LaunchComment}"

[Run]
; Флажок после установки: запустить кошелёк.
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent unchecked

[CustomMessages]
russian.LaunchComment=Некастодиальный мультивалютный кошелёк
english.LaunchComment=Self-custodial multi-cryptocurrency wallet
