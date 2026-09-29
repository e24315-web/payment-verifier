# Makes PaymentVerifier.zip to copy to another PC. Leaves out the venv (PC-specific), node_modules,
# the local database and uploaded slips, caches and the legacy prototype.
#   -IncludeData   also copy the database and uploaded slips
param([switch]$IncludeData)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot "build_exe.ps1")

$outDir = Join-Path $Root "package"
$stage = Join-Path $outDir "payment-verifier"
$zip = Join-Path $outDir "PaymentVerifier.zip"
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
New-Item -ItemType Directory -Force $stage | Out-Null

$skipDirs = @("venv", "node_modules", "__pycache__", ".pytest_cache", "legacy", "package", "my_slips")
$skipFiles = @("*.pyc")
if (-not $IncludeData) {
    $skipDirs += "uploads"
    $skipFiles += @("*.db", "*.db-wal", "*.db-shm")
}
# robocopy exit codes below 8 mean success
robocopy $Root $stage /E /NFL /NDL /NJH /NJS /NP /XD $skipDirs /XF $skipFiles | Out-Null
if ($LASTEXITCODE -ge 8) { throw "copy failed ($LASTEXITCODE)" }

Compress-Archive -Path $stage -DestinationPath $zip -Force
Remove-Item -Recurse -Force $stage
Write-Host "Package ready: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
exit 0
