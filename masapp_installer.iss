#ifndef MyAppName
  #define MyAppName "MASAPP"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef MyAppPublisher
  #define MyAppPublisher "jetsoft co.,ltd"
#endif
#ifndef MyAppExeName
  #define MyAppExeName "masapp.exe"
#endif
#ifndef MyBuildDir
  #define MyBuildDir "build\windows\x64\runner\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "Output"
#endif

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir={#MyOutputDir}
OutputBaseFilename=MASAPP_Setup_v{#MyAppVersion}
Compression=lzma
SolidCompression=yes
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName},0
DisableProgramGroupPage=yes
DisableDirPage=auto
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; 

[Files]
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; IconIndex: 0
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; IconIndex: 0; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\*"
Type: dirifempty; Name: "{app}"

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /F /IM {#MyAppExeName}"; Flags: runhidden skipifdoesntexist; RunOnceId: "Kill{#MyAppName}Process"

[Code]
var
  RemoveAppDataOnUninstall: Boolean;

procedure DeleteFileIfExists(const FilePath: string);
begin
  if FileExists(FilePath) then
  begin
    DeleteFile(FilePath);
  end;
end;

procedure RemoveDirIfEmptySafe(const DirPath: string);
begin
  if DirExists(DirPath) then
  begin
    RemoveDir(DirPath);
  end;
end;

procedure DeleteAppDataFiles();
var
  UserDataRoot: string;
  LegacyNestedRoot: string;
  DocumentsRoot: string;
  InstallLocalConfigRoot: string;
begin
  UserDataRoot := ExpandConstant('{userappdata}\com.masapp\masapp');
  LegacyNestedRoot := UserDataRoot + '\masapp';
  DocumentsRoot := ExpandConstant('{userdocs}\MASAPP');
  InstallLocalConfigRoot := ExpandConstant('{app}\.masapp');

  { Remove only client-side app state. Do not touch any configured database path. }
  DeleteFileIfExists(UserDataRoot + '\config.json');
  DeleteFileIfExists(UserDataRoot + '\shared_preferences.json');
  DeleteFileIfExists(LegacyNestedRoot + '\config.json');
  DeleteFileIfExists(DocumentsRoot + '\config.json');
  DeleteFileIfExists(InstallLocalConfigRoot + '\config.json');

  RemoveDirIfEmptySafe(LegacyNestedRoot);
  RemoveDirIfEmptySafe(DocumentsRoot);
  RemoveDirIfEmptySafe(InstallLocalConfigRoot);
  RemoveDirIfEmptySafe(UserDataRoot);
  RemoveDirIfEmptySafe(ExpandConstant('{userappdata}\com.masapp'));
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  // Check if it's already installed (by checking the uninstall registry key)
  if RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppName}_is1') or
     RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppName}_is1') or
     RegKeyExists(HKEY_CURRENT_USER, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppName}_is1') then
  begin
    if MsgBox('ตรวจพบว่ามีโปรแกรม {#MyAppName} ติดตั้งอยู่ในเครื่องนี้แล้ว' + #13#10 + 'คุณต้องการติดตั้งทับเพื่อ อัปเดต หรือ ซ่อมแซม (Repair) ใช่หรือไม่?', mbConfirmation, MB_YESNO) = IDNO then
    begin
      Result := False;
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    RemoveAppDataOnUninstall :=
      MsgBox(
        'ต้องการลบข้อมูลแอปบนเครื่องนี้ด้วยหรือไม่?' + #13#10#13#10 +
        'ระบบจะลบเฉพาะ config และข้อมูลจำการเข้าสู่ระบบของแอปบนเครื่องนี้เท่านั้น' + #13#10 +
        'ระบบจะไม่ลบฐานข้อมูลที่ตั้งค่าไว้ และจะไม่แตะฐานข้อมูลบน network',
        mbConfirmation,
        MB_YESNO
      ) = IDYES;

    if RemoveAppDataOnUninstall then
    begin
      DeleteAppDataFiles();
    end;
  end;
end;
