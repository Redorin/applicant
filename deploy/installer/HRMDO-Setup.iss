; Inno Setup script for the HRMDO Applicants Information System.
; Bundles the published API and the Flutter Windows release build, plus the
; existing launcher scripts (deploy\Start-HRMDO.ps1) that start the API on
; demand and then open the app.
;
; Build: run deploy\build.ps1 first, then compile this script with ISCC.
;
; Requirements on the TARGET machine (not installed by this setup):
;   - .NET 10 runtime (for the API)
;   - SQL Server on 192.168.2.156:1433 with the "Applicants Updated" database

#define MyAppName "HRMDO Applicants System"
#define MyAppVersion "3.0.0"
#define MyAppPublisher "HRMDO, Province of Pangasinan"
#define MyAppExeName "app\applicants_app.exe"
#define DeployDir "..\"

[Setup]
AppId={{8E4F2C1A-6B3D-4E7A-9C2F-1D5A7B3E9F04}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=HRMDO-Applicants-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\frontend\applicants_app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#DeployDir}app\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#DeployDir}api\*"; DestDir: "{app}\api"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#DeployDir}Start-HRMDO.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Start-HRMDO.ps1"""; \
  WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Start-HRMDO.ps1"""; \
  WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Start-HRMDO.ps1"""; \
  WorkingDir: "{app}"; Description: "Launch {#MyAppName}"; Flags: postinstall nowait skipifsilent

[UninstallRun]
; Stop the API/app if running so the uninstaller can remove the files.
Filename: "taskkill.exe"; Parameters: "/F /IM dotnet.exe /T"; Flags: runhidden skipifdoesntexist; RunOnceId: "StopApi"
Filename: "taskkill.exe"; Parameters: "/F /IM applicants_app.exe /T"; Flags: runhidden skipifdoesntexist; RunOnceId: "StopApp"

[Messages]
FinishedLabel=Setup has installed {#MyAppName}.%n%nThis machine must have .NET 10 runtime and SQL Server on 192.168.2.156 with the "Applicants Updated" database for the app to work.%n%nYou can now run the application via the shortcut.

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  Lines: TArrayOfString;
  i: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    if LoadStringsFromFile(ExpandConstant('{app}\api\appsettings.json'), Lines) then
    begin
      for i := 0 to GetArrayLength(Lines) - 1 do
      begin
        StringChangeEx(Lines[i],
          'Data Source=.\\SQLEXPRESS;Initial Catalog=Applicants;Integrated Security=True;TrustServerCertificate=True',
          'Data Source=192.168.2.156,1433;Initial Catalog=Applicants Updated;User ID=app_remote;Password=Applicants2026!;TrustServerCertificate=True',
          False);
      end;
      SaveStringsToFile(ExpandConstant('{app}\api\appsettings.json'), Lines, False);
    end;
  end;
end;
