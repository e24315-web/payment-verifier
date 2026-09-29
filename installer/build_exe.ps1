# Compiles installer\Launcher.cs into "Payment Verifier.exe" in the project root (uses the .NET Framework
# compiler that ships with Windows; nothing to install).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$out = Join-Path $Root "Payment Verifier.exe"
& $csc /nologo /target:exe /optimize+ "/out:$out" (Join-Path $PSScriptRoot "Launcher.cs")
if ($LASTEXITCODE -ne 0) { throw "compile failed" }
Write-Host "Built $out"
