# build_release_windows.ps1 — Build Stock Plan Manager Windows installer.
#
# Run from the project root (or any directory — the script cd's to root).
# Produces release\StockPlan-Setup.exe.
#
# Prerequisites (one-time on the build machine, NOT on the end user's PC):
#   - Erlang OTP for Windows         https://www.erlang.org/downloads
#   - Elixir for Windows             https://elixir-lang.org/install.html#windows
#   - Inno Setup 6                   https://jrsoftware.org/isdl.php
#   - Visual Studio Build Tools      https://visualstudio.microsoft.com/downloads/
#       (or any clang/cl with Windows SDK)

# NOTE: deliberately NOT "Stop". Elixir's mix.ps1 wrapper inherits this
# preference; under "Stop", PowerShell 5.1 escalates mix's *stderr warnings*
# (e.g. compile type-warnings) into a terminating NativeCommandError, aborting
# the build even though mix exits 0. We drive native build tools (mix, cl,
# ISCC) and check $LASTEXITCODE explicitly after each instead.
$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
Set-Location $ProjectRoot

Write-Host "==> Project root: $ProjectRoot"

# -- Tool locations ---------------------------------------------------------

$InnoCandidates = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$InnoSetupCompiler = $InnoCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $InnoSetupCompiler) {
    throw "Inno Setup (ISCC.exe) not found. Looked in: $($InnoCandidates -join '; '). Install from https://jrsoftware.org/isdl.php"
}

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw "cl.exe not on PATH. Run this script from a 'x64 Native Tools Command Prompt' or call vcvars64.bat first."
}

if (-not (Get-Command mix.bat -ErrorAction SilentlyContinue) -and
    -not (Get-Command mix -ErrorAction SilentlyContinue)) {
    throw "Elixir's mix not on PATH. Install Elixir for Windows and reopen the shell."
}

# -- Build steps ------------------------------------------------------------

Write-Host "==> Fetching prod dependencies"
$env:MIX_ENV = "prod"
mix deps.get --only prod
if ($LASTEXITCODE -ne 0) { throw "mix deps.get failed" }

Write-Host "==> Compiling app (generates phoenix-colocated JS hooks needed by esbuild)"
mix compile
if ($LASTEXITCODE -ne 0) { throw "mix compile failed" }

Write-Host "==> Building assets"
mix assets.deploy
if ($LASTEXITCODE -ne 0) { throw "mix assets.deploy failed" }

Write-Host "==> Building Mix release"
mix release --overwrite
if ($LASTEXITCODE -ne 0) { throw "mix release failed" }

# -- Compile native launcher ------------------------------------------------

Write-Host "==> Compiling native launcher (StockPlan.exe)"
$LauncherSrc = "scripts\launcher_win.c"
$LauncherOut = "scripts\StockPlan.exe"
& cl /nologo /O2 /W3 /Fe:$LauncherOut $LauncherSrc /link winhttp.lib shell32.lib /SUBSYSTEM:WINDOWS
if ($LASTEXITCODE -ne 0) { throw "Launcher compile failed" }

# -- Generate a multi-size .ico from docs\Logo.png -------------------------
# Build a proper multi-resolution icon (16..256px) with high-quality
# resampling and PNG-compressed entries (Windows 10+ reads PNG icon data at
# every size). The old Bitmap.GetHicon path emitted a single, soft 256px image
# that Windows then downscaled badly for Start Menu / shortcut sizes.

Write-Host "==> Generating multi-size Logo.ico from docs\Logo.png"
Add-Type -AssemblyName System.Drawing
$PngPath = Join-Path $ProjectRoot "docs\Logo.png"
$IcoPath = Join-Path $ProjectRoot "docs\Logo.ico"
if (Test-Path $PngPath) {
    $png = [System.Drawing.Image]::FromFile($PngPath)
    try {
        # Centered square crop (source is a wide banner around a centered badge).
        $minDim = [Math]::Min($png.Width, $png.Height)
        $srcX = [int](($png.Width  - $minDim) / 2)
        $srcY = [int](($png.Height - $minDim) / 2)
        $srcRect = New-Object System.Drawing.Rectangle $srcX, $srcY, $minDim, $minDim

        $sizes = @(16, 24, 32, 48, 64, 128, 256)
        $pngBlobs = @()
        foreach ($s in $sizes) {
            $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode   = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.PixelOffsetMode     = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.SmoothingMode       = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.CompositingQuality  = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.DrawImage($png, (New-Object System.Drawing.Rectangle 0, 0, $s, $s), $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
            $g.Dispose()
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $pngBlobs += ,($ms.ToArray())
            $ms.Dispose()
            $bmp.Dispose()
        }

        # Assemble the ICO container: ICONDIR + ICONDIRENTRY[] + PNG payloads.
        $fs = [System.IO.File]::Create($IcoPath)
        $bw = New-Object System.IO.BinaryWriter $fs
        $bw.Write([UInt16]0)             # reserved
        $bw.Write([UInt16]1)             # type = icon
        $bw.Write([UInt16]$sizes.Count)  # image count
        $offset = 6 + (16 * $sizes.Count)
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $s = $sizes[$i]
            $dim = $(if ($s -ge 256) { 0 } else { $s })   # 0 in the dir means 256
            $bw.Write([Byte]$dim)        # width
            $bw.Write([Byte]$dim)        # height
            $bw.Write([Byte]0)           # palette color count
            $bw.Write([Byte]0)           # reserved
            $bw.Write([UInt16]1)         # color planes
            $bw.Write([UInt16]32)        # bits per pixel
            $bw.Write([UInt32]$pngBlobs[$i].Length)
            $bw.Write([UInt32]$offset)
            $offset += $pngBlobs[$i].Length
        }
        foreach ($blob in $pngBlobs) { $bw.Write($blob) }
        $bw.Flush(); $bw.Close(); $fs.Close()
        Write-Host "    Wrote $($sizes.Count)-size icon ($($sizes -join ', ')px)"
    } finally {
        $png.Dispose()
    }
} else {
    Write-Host "    docs\Logo.png not found — Inno Setup will fail unless a Logo.ico already exists."
}

# -- Download VC++ Redistributable -----------------------------------------

Write-Host "==> Ensuring vcredist_x64.exe is present"
$VCRedistOut = Join-Path $ScriptDir "vcredist_x64.exe"
if (-not (Test-Path $VCRedistOut)) {
    $VCRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    Invoke-WebRequest -Uri $VCRedistUrl -OutFile $VCRedistOut -UseBasicParsing
}

# -- Build installer --------------------------------------------------------

Write-Host "==> Building installer with Inno Setup"
# Extract the version from mix.exs so .iss + mix.exs stay in lockstep —
# every release bump only needs `mix.exs` changed.
$MixContent = Get-Content -Raw -Path (Join-Path $ProjectRoot "mix.exs")
if ($MixContent -match 'version:\s*"([^"]+)"') {
    $AppVersion = $Matches[1]
} else {
    throw "Could not extract version from mix.exs"
}
Write-Host "    Using version: $AppVersion"

& $InnoSetupCompiler "/DMyAppVersion=$AppVersion" scripts\StockPlan.iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compile failed" }

# -- Cleanup transient artifacts -------------------------------------------

Remove-Item $LauncherOut -ErrorAction SilentlyContinue
Remove-Item (Join-Path $ScriptDir "StockPlan.exp") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $ScriptDir "StockPlan.lib") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $ScriptDir "launcher_win.obj") -ErrorAction SilentlyContinue

# -- Done -------------------------------------------------------------------

$InstallerPath = Join-Path $ProjectRoot "release\StockPlan-Setup.exe"
Write-Host ""
Write-Host "Built:"
Get-ChildItem $InstallerPath | Format-List Name, FullName, Length, LastWriteTime

Write-Host ""
Write-Host "Compute SHA256:"
(Get-FileHash $InstallerPath -Algorithm SHA256).Hash
