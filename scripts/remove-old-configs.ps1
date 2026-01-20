# ---- Variables ----
$NxlogDDir   = "C:\Program Files\nxlog\conf\nxlog.d"
$KeepFile   = "managed.conf"

function Fail {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

# ---- Safety Checks ----
if (-not (Test-Path $NxlogDDir)) {
    Fail "Directory not found: $NxlogDDir"
}

Write-Host "Cleaning NXLog directory: $NxlogDDir" -ForegroundColor Cyan
Write-Host "Preserving file: $KeepFile" -ForegroundColor Green

# ---- List files to be removed (preview) ----
$filesToRemove = Get-ChildItem -Path $NxlogDDir -File |
    Where-Object { $_.Name -ne $KeepFile }

if (-not $filesToRemove) {
    Write-Host "[OK] No files to remove. Directory already clean." -ForegroundColor Green
    return
}

Write-Host "`nFiles that will be removed:" -ForegroundColor Yellow
$filesToRemove | ForEach-Object {
    Write-Host " - $($_.Name)"
}

# ---- Remove files ----
$filesToRemove | Remove-Item -Force -Confirm:$false

Write-Host "`n[SUCCESS] Cleanup complete. Only '$KeepFile' remains." -ForegroundColor Green
