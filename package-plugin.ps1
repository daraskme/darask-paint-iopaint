# Builds the darask-paint plugin zip: drop the result into darask-paint's
# `plugins` folder (next to darask-paint.exe, or the folder configured in
# Settings) and the app extracts + launches it on first use.
#
#   pwsh ./package-plugin.ps1 [-Version plugin-v1.0.0] [-OutDir dist]
#   -> dist/darask-paint-iopaint-plugin-v1.0.0.zip
#
# The zip only carries the launcher, its manifest and docs. The IOpaint
# engine itself is still installed by darask-plugin.bat on first run
# (pinned tag, %LOCALAPPDATA%\IOPaint), exactly as when run from a clone.
param(
    [string]$Version = "plugin-dev",
    [string]$OutDir = "dist"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$files = @("darask-plugin.bat", "darask-plugin.json", "README.md", "LICENSE")
foreach ($file in $files) {
    if (-not (Test-Path (Join-Path $root $file))) { throw "missing $file" }
}

$manifest = Get-Content (Join-Path $root "darask-plugin.json") -Raw | ConvertFrom-Json
if ($manifest.name -ne "iopaint") { throw "manifest name must be 'iopaint'" }
if ($manifest.launcher -ne "darask-plugin.bat") { throw "manifest launcher must be darask-plugin.bat" }

$name = "darask-paint-iopaint-$Version"
$stage = Join-Path ([IO.Path]::GetTempPath()) ("darask-plugin-pkg-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path (Join-Path $stage $name) | Out-Null
foreach ($file in $files) {
    Copy-Item (Join-Path $root $file) (Join-Path $stage $name)
}

New-Item -ItemType Directory -Path (Join-Path $root $OutDir) -Force | Out-Null
$zip = Join-Path (Resolve-Path (Join-Path $root $OutDir)).Path "$name.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $stage $name) -DestinationPath $zip
Remove-Item -Recurse -Force $stage
Write-Output $zip
