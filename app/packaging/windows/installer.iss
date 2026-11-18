[Setup]
AppId={{324A1174-61F6-4E79-A197-CBB409057A19}
AppName=Mosterdzaad
AppVersion=0.2.0
AppPublisher=Mosterdzaad
DefaultDirName={localappdata}\Programs\Mosterdzaad
DefaultGroupName=Mosterdzaad
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\packages
OutputBaseFilename=Mosterdzaad-windows-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mosterdzaad.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Mosterdzaad"; Filename: "{app}\mosterdzaad.exe"
[Run]
Filename: "{app}\mosterdzaad.exe"; Description: "Mosterdzaad openen"; Flags: nowait postinstall skipifsilent
