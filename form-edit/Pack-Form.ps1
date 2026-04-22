[CmdletBinding()]
param(
    [string]$UnpackedDir,
    [string]$DistDir
)

$ErrorActionPreference = 'Stop'

# Resolve the script's own directory without relying on $scriptRoot in param defaults.
$scriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }

if (-not $UnpackedDir) { $UnpackedDir = Join-Path $scriptRoot 'unpacked' }
if (-not $DistDir)     { $DistDir     = Join-Path $scriptRoot 'dist' }

Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    throw "Power Platform CLI ('pac') not found on PATH. Install with: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
}

if (-not (Test-Path $UnpackedDir) -or -not (Get-ChildItem -Path $UnpackedDir -Recurse -File | Select-Object -First 1)) {
    throw "Unpacked folder is empty: '$UnpackedDir'. Run 1-Unpack.bat first."
}

$stateFile = Join-Path $scriptRoot '.last-source.json'
if (-not (Test-Path $stateFile)) {
    throw "Missing state file '.last-source.json'. Re-run 1-Unpack.bat to regenerate."
}
$state = Get-Content -Path $stateFile -Raw | ConvertFrom-Json

$origName = $state.SourceName
$wasZip   = [bool]$state.WasZip
$stem     = [System.IO.Path]::GetFileNameWithoutExtension($origName)
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir | Out-Null }

# Always rebuild the .msapp via pac canvas pack.
$msappTmp = Join-Path $env:TEMP ("form-edit-" + [Guid]::NewGuid().ToString('N') + ".msapp")
Write-Host "Packing via 'pac canvas pack' -> $msappTmp" -ForegroundColor Cyan
pac canvas pack --sources "$UnpackedDir" --msapp "$msappTmp"
if ($LASTEXITCODE -ne 0) {
    if (Test-Path $msappTmp) { Remove-Item $msappTmp -Force -ErrorAction SilentlyContinue }
    throw "pac canvas pack failed with exit code $LASTEXITCODE"
}

if (-not $wasZip) {
    # Source was .msapp - emit .msapp.
    $outName = "{0}.edited-{1}.msapp" -f $stem, $stamp
    $outPath = Join-Path $DistDir $outName
    Move-Item -Path $msappTmp -Destination $outPath -Force
    Write-Host ""
    Write-Host "Done. Load this .msapp into Studio (Open -> Browse):" -ForegroundColor Green
    Write-Host "  $outPath" -ForegroundColor Green
    return
}

# Source was .zip - rebuild the outer package the way Power Apps accepts.
# Recipe matches FlowPowerAppsMigrator/ConvertPackage.ps1:
#   [System.IO.Compression.ZipFile]::CreateFromDirectory(dir, zipPath, CompressionLevel::Optimal, includeBaseDirectory=$false)
$stagingDir   = $state.StagingDir
$msappRelPath = $state.MsappRelPath
if (-not $stagingDir -or -not (Test-Path $stagingDir)) {
    if (Test-Path $msappTmp) { Remove-Item $msappTmp -Force -ErrorAction SilentlyContinue }
    throw "Staging directory from unpack not found at '$stagingDir'. Re-run 1-Unpack.bat."
}
$targetMsapp = Join-Path $stagingDir $msappRelPath
if (-not (Test-Path $targetMsapp)) {
    if (Test-Path $msappTmp) { Remove-Item $msappTmp -Force -ErrorAction SilentlyContinue }
    throw "Embedded msapp path missing in staging: $targetMsapp"
}

Write-Host "Replacing embedded msapp at '$msappRelPath'" -ForegroundColor Cyan
Remove-Item -Path $targetMsapp -Force
Move-Item -Path $msappTmp -Destination $targetMsapp -Force

$outName = "{0}.edited-{1}.zip" -f $stem, $stamp
$outPath = Join-Path $DistDir $outName
if (Test-Path $outPath) { Remove-Item $outPath -Force }

Write-Host "Zipping outer package (Optimal, no base dir) -> $outPath" -ForegroundColor Cyan
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stagingDir,
    $outPath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

Write-Host ""
Write-Host "Done. Import this .zip via Power Apps (Apps -> Import canvas app):" -ForegroundColor Green
Write-Host "  $outPath" -ForegroundColor Green
