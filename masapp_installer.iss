[Setup]
AppName=MASAPP
AppVersion=1.0.0
AppPublisher=jetsoft co.,ltd
DefaultDirName={autopf}\MASAPP
DefaultGroupName=MASAPP
OutputDir=D:\DEV\MASAPP\Output
OutputBaseFilename=MASAPP_Setup_v1.0
Compression=lzma
SolidCompression=yes
SetupIconFile=D:\DEV\MASAPP\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\masapp.exe
DisableProgramGroupPage=yes
DisableDirPage=auto

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; 

[Files]
Source: "D:\DEV\MASAPP\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\MASAPP"; Filename: "{app}\masapp.exe"
Name: "{autodesktop}\MASAPP"; Filename: "{app}\masapp.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\masapp.exe"; Description: "{cm:LaunchProgram,MASAPP}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\*"
Type: dirifempty; Name: "{app}"

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /F /IM masapp.exe"; Flags: runhidden skipifdoesntexist

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
  // Check if it's already installed (by checking the uninstall registry key)
  if RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\MASAPP_is1') or 
     RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\MASAPP_is1') or
     RegKeyExists(HKEY_CURRENT_USER, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\MASAPP_is1') then
  begin
    if MsgBox('ตรวจพบว่ามีโปรแกรม MASAPP ติดตั้งอยู่ในเครื่องนี้แล้ว' + #13#10 + 'คุณต้องการติดตั้งทับเพื่อ อัปเดต หรือ ซ่อมแซม (Repair) ใช่หรือไม่?', mbConfirmation, MB_YESNO) = IDNO then
    begin
      Result := False;
    end;
  end;
end;
