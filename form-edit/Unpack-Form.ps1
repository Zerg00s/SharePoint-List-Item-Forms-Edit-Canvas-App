[CmdletBinding()]
param(
    [string]$SrcDir,
    [string]$UnpackedDir,
    [string]$StagingDir
)

$ErrorActionPreference = 'Stop'

# Resolve the script's own directory without relying on $scriptRoot in param defaults.
$scriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }

if (-not $SrcDir)      { $SrcDir      = Join-Path $scriptRoot 'src' }
if (-not $UnpackedDir) { $UnpackedDir = Join-Path $scriptRoot 'unpacked' }
if (-not $StagingDir)  { $StagingDir  = Join-Path $scriptRoot '.staging' }

Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    throw "Power Platform CLI ('pac') not found on PATH. Install with: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
}

# Pick source: first .msapp or .zip in src/.
$source = Get-ChildItem -Path $SrcDir -File |
    Where-Object { $_.Extension -ieq '.msapp' -or $_.Extension -ieq '.zip' } |
    Select-Object -First 1
if (-not $source) {
    throw "No .msapp or .zip file found in '$SrcDir'. Drop the exported form there and re-run."
}

Write-Host "Found : $($source.FullName)" -ForegroundColor Cyan

# Clean output folders.
if (Test-Path $UnpackedDir) {
    Remove-Item -Path (Join-Path $UnpackedDir '*') -Recurse -Force -ErrorAction SilentlyContinue
}
else {
    New-Item -ItemType Directory -Path $UnpackedDir | Out-Null
}
if (Test-Path $StagingDir) {
    Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Backup the original source.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $SrcDir ("{0}.{1}.bak" -f $source.Name, $stamp)
Copy-Item -Path $source.FullName -Destination $backup
Write-Host "Backup: $backup" -ForegroundColor DarkGray

$msappPath = $null
$wasZip = $false
$msappRelPath = $null

if ($source.Extension -ieq '.msapp') {
    $msappPath = $source.FullName
}
elseif ($source.Extension -ieq '.zip') {
    $wasZip = $true
    Write-Host "Input is a Power Apps export package (.zip). Extracting..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $StagingDir | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($source.FullName, $StagingDir)

    $innerMsapp = Get-ChildItem -Path $StagingDir -Recurse -File -Filter '*.msapp' | Select-Object -First 1
    if (-not $innerMsapp) {
        throw "No embedded .msapp found inside '$($source.Name)'."
    }
    $msappPath = $innerMsapp.FullName
    $msappRelPath = $msappPath.Substring($StagingDir.Length).TrimStart('\', '/')
    Write-Host "  Embedded msapp: $msappRelPath" -ForegroundColor DarkGray
}

Write-Host "Unpacking via 'pac canvas unpack' -> $UnpackedDir" -ForegroundColor Cyan
pac canvas unpack --msapp "$msappPath" --sources "$UnpackedDir"
if ($LASTEXITCODE -ne 0) { throw "pac canvas unpack failed with exit code $LASTEXITCODE" }

# Persist state for Pack-Form.ps1.
$state = [ordered]@{
    SourceName   = $source.Name
    WasZip       = $wasZip
    StagingDir   = if ($wasZip) { $StagingDir }    else { $null }
    MsappRelPath = if ($wasZip) { $msappRelPath } else { $null }
}
$stateFile = Join-Path $scriptRoot '.last-source.json'
$state | ConvertTo-Json | Set-Content -Path $stateFile -Encoding ASCII

# Remove obsolete state file from older script versions.
$oldStateFile = Join-Path $scriptRoot '.last-source.txt'
if (Test-Path $oldStateFile) { Remove-Item $oldStateFile -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "Done. Edit the .pa.yaml files under: $UnpackedDir" -ForegroundColor Green
