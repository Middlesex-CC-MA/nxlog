# ---- Variables ----
$NxlogAddress = 'agents.nxlog.mcc.dom:5515'
$DownloadDir  = Join-Path $env:USERPROFILE 'Downloads'
$ServiceName  = 'nxlog'

function Fail {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

Write-Host "=== NXLog Install (no config deploy) ===" -ForegroundColor Cyan

# ---- Find newest NXLog MSI in Downloads ----
$Msi = Get-ChildItem -Path $DownloadDir -Filter 'nxlog*.msi' -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending |
       Select-Object -First 1

if (-not $Msi) {
    Fail "No NXLog MSI found in $DownloadDir (expected nxlog*.msi)."
}

Write-Host "[OK] Found MSI: $($Msi.FullName)"

# ---- Check if NXLog already installed (registry detection) ----
$nxlogInstalled = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "NXLog*" }

if (-not $nxlogInstalled) {
    $nxlogInstalled = Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "NXLog*" }
}

if (-not $nxlogInstalled) {
    Write-Host "Installing NXLog silently..." -ForegroundColor Yellow

    # NOTE: /i must come before MSI path; /qn is fully silent.
    $Args = @(
        "/i", "`"$($Msi.FullName)`"",
        "NXP_ADDRESS=`"$NxlogAddress`"",
        "/qn",
        "/norestart"
    )

    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $Args -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Fail "NXLog MSI install failed. msiexec exit code: $($proc.ExitCode)"
    }

    Write-Host "[OK] NXLog installed"
} else {
    Write-Host "[OK] NXLog already installed (skipping install)"
}

# ---- Verify service exists (some builds use a different name) ----
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "[WARN] Service '$ServiceName' not found. Checking for any NXLog services..." -ForegroundColor DarkYellow
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*nxlog*" } | Select-Object -First 1
    if (-not $svc) {
        Fail "No NXLog service found after install. Check MSI/logs or confirm the NXLog edition/service name."
    }
    $ServiceName = $svc.Name
    Write-Host "[OK] Found NXLog service: $ServiceName"
}

# ---- Set service startup to Automatic and start it ----
try {
    Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop
} catch {
    Fail "Failed to set '$ServiceName' startup type to Automatic. $($_.Exception.Message)"
}

$svc = Get-Service -Name $ServiceName
if ($svc.Status -ne 'Running') {
    Write-Host "Starting NXLog service '$ServiceName'..." -ForegroundColor Yellow
    try {
        Start-Service -Name $ServiceName -ErrorAction Stop
    } catch {
        Fail "Failed to start service '$ServiceName'. $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 2
}

# ---- Final validation ----
$svc = Get-Service -Name $ServiceName
if ($svc.Status -ne 'Running') {
    Fail "NXLog service is NOT running. Current status: $($svc.Status)"
}

Write-Host "[SUCCESS] NXLog installed (if needed) and service is running." -ForegroundColor Green
Write-Host "Service: $ServiceName" -ForegroundColor Green
Write-Host "NXP_ADDRESS: $NxlogAddress" -ForegroundColor Green
