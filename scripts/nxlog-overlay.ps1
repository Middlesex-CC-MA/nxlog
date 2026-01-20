# ---- Variables ----
$NxlogAddress = "agents.nxlog.mcc.dom:5515"

$DownloadDir  = Join-Path $env:USERPROFILE "Downloads"
$Msi          = Get-ChildItem -Path $DownloadDir -Filter "nxlog*.msi" |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

$NxlogBaseDir = "C:\Program Files\nxlog"
$NxlogConfDir = Join-Path $NxlogBaseDir "conf"
$NxlogDDir    = Join-Path $NxlogConfDir "nxlog.d"

# Source config files expected in Downloads
$WindowsBaselineSrc = Join-Path $DownloadDir "windows-baseline.conf"
$CommonOutputsSrc   = Join-Path $DownloadDir "common-outputs.conf"
$WindowsRouteSrc    = Join-Path $DownloadDir "windows-baseline.route.conf"

# Destination names in nxlog.d
$ManagedDest        = Join-Path $NxlogDDir "managed.conf"   # <-- rename target
$CommonOutputsDest  = Join-Path $NxlogDDir "common-outputs.conf"
$WindowsRouteDest   = Join-Path $NxlogDDir "windows-baseline.route.conf"

$ServiceName = "nxlog"

# ---- Helper ----
function Fail {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

Write-Host "=== NXLog Install + Config Deploy ===" -ForegroundColor Cyan

# ---- Step 1: Validate MSI exists ----
if (-not $Msi) {
    Fail "No NXLog MSI found in $DownloadDir (expected something like nxlog*.msi)."
}

Write-Host "[OK] Found MSI: $($Msi.FullName)"

# ---- Step 2: Validate config files exist ----
foreach ($f in @($WindowsBaselineSrc, $CommonOutputsSrc, $WindowsRouteSrc)) {
    if (-not (Test-Path $f)) {
        Fail "Missing required config file: $f"
    }
}
Write-Host "[OK] All required .conf files found in Downloads"

# ---- Step 3: Install NXLog if not installed (registry-based detection) ----
$nxlogInstalled = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "NXLog*" }

if (-not $nxlogInstalled) {
    $nxlogInstalled = Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "NXLog*" }
}

if (-not $nxlogInstalled) {
    Write-Host "Installing NXLog silently..." -ForegroundColor Yellow

    $Args = @(
        "/i", $Msi.FullName,
        "NXP_ADDRESS=$NxlogAddress",
        "/qn",
        "/norestart"
    )

    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $Args -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Fail "NXLog MSI install failed. msiexec exit code: $($proc.ExitCode)"
    }

    Start-Sleep -Seconds 5
    Write-Host "[OK] NXLog installed"
} else {
    Write-Host "[OK] NXLog already installed"
}

# ---- Step 4: Ensure nxlog.d directory exists ----
foreach ($dir in @($NxlogConfDir, $NxlogDDir)) {
    if (-not (Test-Path $dir)) {
        Write-Host "Creating directory: $dir"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}
Write-Host "[OK] NXLog directories ready"

# ---- Step 5: Set NXP_ADDRESS environment variable (Machine scope) ----
# This makes sure the NXLog service sees the value at runtime.
Write-Host "Setting Machine environment variable NXP_ADDRESS=$NxlogAddress"
[System.Environment]::SetEnvironmentVariable("NXP_ADDRESS", $NxlogAddress, "Machine")

# ---- Step 6: Copy configs (rename windows-baseline.conf -> managed.conf) ----
Write-Host "Deploying configs into: $NxlogDDir" -ForegroundColor Yellow

# Replace managed.conf with windows-baseline.conf content
Copy-Item -Path $WindowsBaselineSrc -Destination $ManagedDest -Force
Write-Host "[OK] windows-baseline.conf copied as managed.conf (replaced if existed)"

# Copy the other configs as-is
Copy-Item -Path $CommonOutputsSrc -Destination $CommonOutputsDest -Force
Write-Host "[OK] common-outputs.conf copied"

Copy-Item -Path $WindowsRouteSrc -Destination $WindowsRouteDest -Force
Write-Host "[OK] windows-baseline.route.conf copied"

# ---- Step 7: Restart NXLog service ----
if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
    Fail "NXLog service '$ServiceName' not found after install."
}

Write-Host "Restarting NXLog service..." -ForegroundColor Yellow
Restart-Service -Name $ServiceName -Force
Start-Sleep -Seconds 2

# ---- Step 8: Validate NXLog service state ----
$svc = Get-Service -Name $ServiceName
if ($svc.Status -ne "Running") {
    Fail "NXLog service is NOT running. Current status: $($svc.Status)"
}

Write-Host "[SUCCESS] NXLog installed, configs deployed, and service running." -ForegroundColor Green
Write-Host "NXP_ADDRESS = $NxlogAddress" -ForegroundColor Green
Write-Host "Managed config deployed to: $ManagedDest" -ForegroundColor Green