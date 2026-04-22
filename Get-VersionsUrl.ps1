[CmdletBinding()]
param(
    [string]$FormUrl
)

$ErrorActionPreference = 'Stop'

if (-not $FormUrl) {
    Write-Host "Paste the customized-form Studio URL (from your browser address bar" -ForegroundColor Cyan
    Write-Host "while the form is open in Power Apps Studio), then press Enter:"      -ForegroundColor Cyan
    $FormUrl = Read-Host "URL"
}

$FormUrl = $FormUrl.Trim().Trim('"').Trim("'")

if ([string]::IsNullOrWhiteSpace($FormUrl)) {
    throw "No URL provided."
}

$uri = [System.Uri]$FormUrl

# Environment ID: supports both "/e/<envid>/..." and "/environments/<envid>/..." shapes.
if ($uri.AbsolutePath -match '/(?:e|environments)/([^/]+)') {
    $envId = $matches[1]
}
else {
    throw "Could not find environment id in URL path: $($uri.AbsolutePath)"
}

# App ID: from the "app-id" query parameter.
# Value may be a bare GUID or URL-encoded "/providers/Microsoft.PowerApps/apps/<GUID>".
$appIdRaw = $null
foreach ($pair in ($uri.Query.TrimStart('?') -split '&')) {
    $kv = $pair -split '=', 2
    if ($kv[0] -ieq 'app-id') {
        $appIdRaw = [System.Uri]::UnescapeDataString($kv[1])
        break
    }
}

if (-not $appIdRaw) {
    throw "Could not find 'app-id' query parameter in URL."
}

$appGuid = ($appIdRaw -split '/') | Where-Object { $_ } | Select-Object -Last 1

if ($appGuid -notmatch '^[0-9a-fA-F-]{36}$') {
    Write-Warning "Parsed app id '$appGuid' does not look like a GUID - continuing anyway."
}

$versionsUrl = "https://make.powerapps.com/environments/$envId/apps/$appGuid/versions"

Write-Host ""
Write-Host "Environment ID : $envId"   -ForegroundColor DarkGray
Write-Host "App ID         : $appGuid" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Versions URL:" -ForegroundColor Cyan
Write-Host $versionsUrl    -ForegroundColor Green

try {
    $versionsUrl | Set-Clipboard
    Write-Host "(copied to clipboard)" -ForegroundColor DarkGray
}
catch {
    Write-Host "(clipboard copy unavailable: $($_.Exception.Message))" -ForegroundColor DarkGray
}

$answer = Read-Host "Open in default browser? (y/N)"
if ($answer -match '^(y|yes)$') {
    Start-Process $versionsUrl
}
