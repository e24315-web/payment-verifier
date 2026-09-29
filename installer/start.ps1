# Payment Verifier launcher (run by "Payment Verifier.exe").
# First run: installs Python 3.12 and Tesseract if missing (via winget), creates venv, installs packages.
# Every run: starts the app on a free port and opens it in the browser. Close this window to stop the app.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Venv = Join-Path $Root "venv"
$VenvPy = Join-Path $Venv "Scripts\python.exe"
$Req = Join-Path $Root "backend\requirements.txt"
$Marker = Join-Path $Venv ".pv-installed"
$Host.UI.RawUI.WindowTitle = "Payment Verifier (close this window to stop the app)"

function Say($msg) { Write-Host "  $msg" -ForegroundColor Cyan }
function Fail($msg) {
    Write-Host ""; Write-Host "  ERROR: $msg" -ForegroundColor Red; Write-Host ""
    Read-Host "  Press Enter to close"; exit 1
}
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
function Winget-Install($id, $name) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Fail "$name is not installed and winget is not available. Install $name manually, then run again."
    }
    Say "Installing $name (a Windows prompt may ask for permission)..."
    & winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path
}

# Returns the command line (e.g. "py -3") of a Python 3.11+ interpreter, or $null.
function Find-Python {
    foreach ($cand in @("py -3", "python", "python3")) {
        $parts = $cand -split " "
        if (-not (Get-Command $parts[0] -ErrorAction SilentlyContinue)) { continue }
        $pre = @($parts | Select-Object -Skip 1)
        try {
            $v = & $parts[0] @pre -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
            if ($LASTEXITCODE -eq 0 -and "$v" -match '^3\.(\d+)$' -and [int]$Matches[1] -ge 11) { return $cand }
        } catch {}
    }
    return $null
}

function Get-FreePort {
    foreach ($p in 8000..8050) {
        $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $p)
        try { $l.Start(); $l.Stop(); return $p } catch {}
    }
    Fail "no free port between 8000 and 8050"
}

Write-Host ""
Write-Host "  ===== Payment Verifier =====" -ForegroundColor Green
Write-Host ""

# 1. Python + packages (only when the venv is missing or requirements changed)
$reqHash = (Get-FileHash $Req -Algorithm SHA256).Hash
$installed = (Test-Path $VenvPy) -and (Test-Path $Marker) -and ((Get-Content $Marker -Raw).Trim() -eq $reqHash)
if (-not $installed) {
    Say "First-time setup. This takes a few minutes; later starts are fast."
    $py = Find-Python
    if (-not $py) {
        Winget-Install "Python.Python.3.12" "Python 3.12"
        $py = Find-Python
        if (-not $py) { Fail "Python was installed but cannot be found yet. Close this window and double-click the app again." }
    }
    if (-not (Test-Path $VenvPy)) {
        Say "Creating the Python environment..."
        $parts = $py -split " "
        $pre = @($parts | Select-Object -Skip 1)
        & $parts[0] @pre -m venv $Venv
        if ($LASTEXITCODE -ne 0) { Fail "could not create the Python environment" }
    }
    Say "Installing packages (needs internet)..."
    & $VenvPy -m pip install --disable-pip-version-check -q -r $Req
    if ($LASTEXITCODE -ne 0) { Fail "package installation failed (check the internet connection and try again)" }
    Set-Content -Path $Marker -Value $reqHash -Encoding ascii
}

# 2. Tesseract (the fast OCR tier). Without it the app still runs on the slower RapidOCR tier.
$tess = (Get-Command tesseract -ErrorAction SilentlyContinue) -or (Test-Path "C:\Program Files\Tesseract-OCR\tesseract.exe")
if (-not $tess) {
    try { Winget-Install "UB-Mannheim.TesseractOCR" "Tesseract OCR" } catch {}
    if (-not (Test-Path "C:\Program Files\Tesseract-OCR\tesseract.exe")) {
        Write-Host "  Tesseract could not be installed; slips will be read with the slower OCR." -ForegroundColor Yellow
    }
}

# 3. Start the app and open the browser once it answers.
$port = Get-FreePort
$url = "http://127.0.0.1:$port"
Start-Job -ArgumentList $url -ScriptBlock {
    param($u)
    for ($i = 0; $i -lt 180; $i++) {
        try { Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 2 | Out-Null; Start-Process $u; return } catch { Start-Sleep 1 }
    }
} | Out-Null

Say "Starting... the browser opens at $url"
Say "Keep this window open while using the app. Close it to stop the app."
Write-Host ""
& $VenvPy (Join-Path $Root "backend\run.py") --port $port
if ($LASTEXITCODE -ne 0) { Fail "the app stopped with an error (see the messages above)" }
