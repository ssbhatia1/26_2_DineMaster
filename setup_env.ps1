# ==============================================================================
# DineMaster — Isolated Project Environment Setup & Provisioning Script
# Prepares project-contained JDK, Flutter SDK, dependencies, and activation
# ==============================================================================

[CmdletBinding()]
param (
    [string]$CustomJdkPath = "",
    [string]$CustomFlutterPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$venvDir = Join-Path $projectRoot ".venv"
$jdkDir = Join-Path $venvDir "jdk"
$flutterDir = Join-Path $venvDir "flutter"
$scriptsDir = Join-Path $venvDir "Scripts"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "       DineMaster — Isolated Environment Provisioning             " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Create directory structure
New-Item -ItemType Directory -Force -Path $venvDir | Out-Null
New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null

# 2. Configure Isolated JDK
Write-Host "`n[1/5] Configuring Project-Isolated JDK 21..." -ForegroundColor Yellow
if (Test-Path (Join-Path $jdkDir "bin\java.exe")) {
    Write-Host "  -> Isolated JDK 21 already present at: $jdkDir" -ForegroundColor Green
} elseif ($CustomJdkPath -and (Test-Path $CustomJdkPath)) {
    Write-Host "  -> Copying JDK from specified path: $CustomJdkPath" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $jdkDir | Out-Null
    Copy-Item -Recurse -Force "$CustomJdkPath\*" "$jdkDir\"
} else {
    # Search common system/project JDK locations
    $candidateJdks = @(
        "C:\Users\ssbha\Desktop\acccount\26_2_DineMaster\.venv\jdk",
        "C:\Program Files\Java\jdk-25",
        "C:\Program Files\Java\jdk-21"
    )
    $found = $false
    foreach ($cand in $candidateJdks) {
        if (Test-Path (Join-Path $cand "bin\java.exe")) {
            Write-Host "  -> Copying JDK from $cand to $jdkDir..." -ForegroundColor Cyan
            New-Item -ItemType Directory -Force -Path $jdkDir | Out-Null
            Copy-Item -Recurse -Force "$cand\*" "$jdkDir\"
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Warning "  -> Could not locate local JDK candidate. Please place OpenJDK 21 inside .venv\jdk"
    }
}

if (Test-Path (Join-Path $jdkDir "bin\java.exe")) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $ver = & (Join-Path $jdkDir "bin\java.exe") -version 2>&1 | Select-Object -First 1
    $ErrorActionPreference = $prevEap
    Write-Host "  -> Verified Isolated Java: $ver" -ForegroundColor Green
}

# 3. Configure Isolated Flutter SDK
Write-Host "`n[2/5] Configuring Project-Isolated Flutter SDK..." -ForegroundColor Yellow
if (Test-Path (Join-Path $flutterDir "bin\flutter.bat")) {
    Write-Host "  -> Isolated Flutter SDK already present at: $flutterDir" -ForegroundColor Green
} elseif ($CustomFlutterPath -and (Test-Path $CustomFlutterPath)) {
    Write-Host "  -> Linking Flutter from specified path: $CustomFlutterPath" -ForegroundColor Cyan
    cmd /c "mklink /J `"$flutterDir`" `"$CustomFlutterPath`""
} else {
    $candidateFlutters = @(
        "C:\Flutter\flutter_windows_3.41.3-stable\flutter",
        "C:\src\flutter",
        "C:\flutter"
    )
    $foundFlutter = $false
    foreach ($cand in $candidateFlutters) {
        if (Test-Path (Join-Path $cand "bin\flutter.bat")) {
            Write-Host "  -> Linking Flutter SDK from $cand..." -ForegroundColor Cyan
            cmd /c "mklink /J `"$flutterDir`" `"$cand`""
            $foundFlutter = $true
            break
        }
    }
    if (-not $foundFlutter) {
        # Check if flutter is in existing PATH
        $globalFlutter = Get-Command flutter -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        if ($globalFlutter) {
            $flutterRootCand = (Resolve-Path "$globalFlutter\..\..").Path
            Write-Host "  -> Linking Flutter SDK from detected location $flutterRootCand..." -ForegroundColor Cyan
            cmd /c "mklink /J `"$flutterDir`" `"$flutterRootCand`""
        } else {
            Write-Warning "  -> Could not locate Flutter SDK. Please link or place Flutter SDK inside .venv\flutter"
        }
    }
}

# 4. Resolve Frontend Dependencies
Write-Host "`n[3/5] Resolving Frontend Flutter Dependencies..." -ForegroundColor Yellow
$flutterBin = Join-Path $flutterDir "bin\flutter.bat"
if (Test-Path $flutterBin) {
    Push-Location (Join-Path $projectRoot "frontend")
    try {
        & $flutterBin pub get
        Write-Host "  -> Frontend dependencies resolved successfully." -ForegroundColor Green
    } finally {
        Pop-Location
    }
} else {
    Write-Warning "  -> Skipped frontend dependencies (Flutter binary not yet available)."
}

# 5. Resolve Backend Dependencies & Build Tools
Write-Host "`n[4/5] Pre-compiling Backend Dependencies via Maven Wrapper..." -ForegroundColor Yellow
$mvnwBin = Join-Path $projectRoot "backend\mvnw.cmd"
if (Test-Path $mvnwBin) {
    Push-Location (Join-Path $projectRoot "backend")
    try {
        $env:JAVA_HOME = $jdkDir
        & $mvnwBin test-compile
        Write-Host "  -> Backend Maven build tools and dependencies verified." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# 6. Verify Activation Readiness
Write-Host "`n[5/5] Checking Environment Activation Readiness..." -ForegroundColor Yellow
Write-Host "  -> PowerShell Activation: .\Activate.ps1" -ForegroundColor Cyan
Write-Host "  -> CMD Activation:        .\activate.bat" -ForegroundColor Cyan
Write-Host "  -> Bash Activation:       source ./activate.sh" -ForegroundColor Cyan

Write-Host "`n==================================================================" -ForegroundColor Green
Write-Host "   DineMaster Isolated Environment Setup Completed Successfully!  " -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
