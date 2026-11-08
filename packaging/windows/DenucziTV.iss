; Build with Inno Setup 7 through scripts/package-windows.ps1.
; Application source and packaging tools may belong to different checkouts.
#ifndef AppVersion
  #error Supply AppVersion using --define=AppVersion=0.6.2
#endif
#define AppName "DenucziTV"
#define AppExecutable "denuczi_tv.exe"
#ifndef ProjectRoot
  #error Supply ProjectRoot using the package-windows.ps1 entry point.
#endif
#define ApplicationRoot AddBackslash(ProjectRoot)
#define BundleDir ApplicationRoot + "build\windows\x64\runner\Release"

#if !FileExists(BundleDir + "\" + AppExecutable)
  #error The Windows x64 release executable is missing.
#endif
#if !FileExists(BundleDir + "\flutter_windows.dll")
  #error The Flutter runtime is missing.
#endif
#if !FileExists(BundleDir + "\libmpv-2.dll")
  #error The media playback runtime is missing.
#endif
#if !FileExists(BundleDir + "\data\app.so")
  #error The release AOT application is missing.
#endif
#if !FileExists(BundleDir + "\msvcp140.dll") || !FileExists(BundleDir + "\vcruntime140.dll") || !FileExists(BundleDir + "\vcruntime140_1.dll")
  #error Copy the official x64 Visual C++ release runtime DLLs into the bundle first.
#endif

[Setup]
; Keep this identity unchanged for subsequent installers of the same application.
AppId={{D8CE0BC3-AE12-4CE1-9F41-62BBFFBD9F39}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Denuczi
AppPublisherURL=https://github.com/denuczi/DenucziTV
AppSupportURL=https://github.com/denuczi/DenucziTV/issues
AppUpdatesURL=https://github.com/denuczi/DenucziTV/releases/latest
VersionInfoVersion={#GetVersionNumbersString(BundleDir + "\" + AppExecutable)}
DefaultDirName={localappdata}\Programs\DenucziTV
DefaultGroupName=DenucziTV
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
SetupArchitecture=x64
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#ApplicationRoot}dist
OutputBaseFilename=DenucziTV-Setup-{#AppVersion}-x64
SetupIconFile={#ApplicationRoot}assets\branding\denuczitv.ico
UninstallDisplayIcon={app}\{#AppExecutable}
LicenseFile={#ApplicationRoot}LICENSE
WizardStyle=modern
Compression=lzma2/normal
CompressionThreads=2
LZMANumBlockThreads=1
SolidCompression=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Keep all runtime libraries and assets together. PDBs are debugging symbols.
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ApplicationRoot}LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\DenucziTV"; Filename: "{app}\{#AppExecutable}"; WorkingDir: "{app}"
Name: "{autodesktop}\DenucziTV"; Filename: "{app}\{#AppExecutable}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExecutable}"; Description: "{cm:LaunchProgram,{#AppName}}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
