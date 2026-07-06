; Inno Setup script for Stock Plan Manager
; Produces release\StockPlan-Setup.exe — self-contained installer that
; bundles the Phoenix release (with Erlang ERTS), a native launcher,
; install guide, and Visual C++ Redistributable.

#define MyAppName "Stock Plan Manager"
#define MyAppShortName "StockPlan"
; Version is normally injected by build_release_windows.ps1 via
; ISCC /DMyAppVersion=X.Y.Z. The fallback below only fires if the
; script is invoked manually (e.g., from the Inno Setup IDE) so the
; compile still succeeds.
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0-dev"
#endif
#define MyAppPublisher "Arthium"
#define MyAppURL "https://github.com/Arthium-Org/stock-plan-companion-app"
#define MyAppExeName "StockPlan.exe"

[Setup]
; AppId — keep stable across versions so upgrades replace cleanly.
AppId={{C8E7F3B4-9D2A-4F1E-A8C6-7B5E9D2F4A1C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppShortName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\release
OutputBaseFilename={#MyAppShortName}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\docs\Logo.ico
LicenseFile=
; Refuse to install on anything older than Windows 10 1809 (build 17763).
MinVersion=10.0.17763

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
; The Phoenix release tree (built by build_release_windows.ps1 ahead of ISCC).
Source: "..\_build\prod\rel\stock_plan\*"; DestDir: "{app}\release"; Flags: ignoreversion recursesubdirs createallsubdirs

; Native launcher built by the PowerShell script.
Source: "StockPlan.exe"; DestDir: "{app}"; Flags: ignoreversion

; App icon (.ico, generated from docs\Logo.png by the build script).
Source: "..\docs\Logo.ico"; DestDir: "{app}"; Flags: ignoreversion

; User-facing install guide opened from the Start Menu.
Source: "install_guide_windows.html"; DestDir: "{app}"; DestName: "Install Guide.html"; Flags: ignoreversion

; Microsoft VC++ Runtime — bundled, installed silently below if missing.
Source: "vcredist_x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\Logo.ico"
Name: "{group}\Install Guide"; Filename: "{app}\Install Guide.html"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\Logo.ico"; Tasks: desktopicon

[Run]
; VC++ Runtime is NOT installed here. It runs from [Code] (CurStepChanged at
; ssPostInstall) so we can switch the progress bar to an animated marquee with
; a clear message during the slow runtime install — otherwise the bar sits
; pinned at 100% with no motion and looks frozen. See CurStepChanged below.

; Launch the app at the end of install (user can uncheck).
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; \
    Flags: nowait postinstall skipifsilent

[UninstallRun]
; Best-effort: stop the BEAM if it's running before uninstall removes files.
Filename: "{cmd}"; Parameters: "/c taskkill /F /IM erl.exe /T"; Flags: runhidden; RunOnceId: "stopbeam_erl"
Filename: "{cmd}"; Parameters: "/c taskkill /F /IM erlsrv.exe /T"; Flags: runhidden; RunOnceId: "stopbeam_erlsrv"
Filename: "{cmd}"; Parameters: "/c taskkill /F /IM {#MyAppExeName} /T"; Flags: runhidden; RunOnceId: "stoplauncher"

[Code]
function VCRedistNeedsInstall: Boolean;
var
  Version: String;
begin
  // VC++ 2015-2022 (14.x) installs into HKLM Runtimes\x64 key.
  if RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
                          'Version', Version) then
    Result := False
  else
    Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  // ssPostInstall fires after files are copied while the install page (and its
  // progress bar) are still visible — the right place to run the bundled VC++
  // runtime with live feedback.
  if (CurStep = ssPostInstall) and VCRedistNeedsInstall then
  begin
    WizardForm.StatusLabel.Caption :=
      'Installing Microsoft Visual C++ Runtime — this can take a minute...';
    // Marquee = continuous motion so the (already-full) bar no longer looks
    // frozen. Inno keeps the message loop alive during Exec, so it animates.
    WizardForm.ProgressGauge.Style := npbstMarquee;
    try
      Exec(ExpandConstant('{tmp}\vcredist_x64.exe'),
           '/install /quiet /norestart', '',
           SW_HIDE, ewWaitUntilTerminated, ResultCode);
    finally
      WizardForm.ProgressGauge.Style := npbstNormal;
      WizardForm.ProgressGauge.Position := WizardForm.ProgressGauge.Max;
      WizardForm.StatusLabel.Caption := 'Finishing up...';
    end;
  end;
end;
