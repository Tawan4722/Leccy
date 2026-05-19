[Setup]
AppName=Leccy
AppVersion=1.0
DefaultDirName={autopf}\Leccy
DefaultGroupName=Leccy
OutputBaseFilename=LeccySetup
Compression=lzma
SolidCompression=yes
SetupIconFile="{#SourcePath}\windows\runner\resources\app_icon.ico"

[Files]
; IMPORTANT: Ensure you have run 'flutter build windows --release' first.
Source: "{#SourcePath}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Leccy"; Filename: "{app}\leccy.exe"; IconFilename: "{app}\leccy.exe"
Name: "{autodesktop}\Leccy"; Filename: "{app}\leccy.exe"; IconFilename: "{app}\leccy.exe"
