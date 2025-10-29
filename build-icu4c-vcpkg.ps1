$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutputDir = Join-Path $ScriptDir "target\x86_64-pc-windows-msvc\icu4c"

Write-Host "Installing ICU with vcpkg..."
vcpkg install icu:x64-windows-static

Write-Host "Copying ICU files..."
$VcpkgInstalled = Join-Path $env:VCPKG_ROOT "packages\icu_x64-windows-static"

New-Item -ItemType Directory -Force -Path "$OutputDir\lib" | Out-Null
New-Item -ItemType Directory -Force -Path "$OutputDir\include" | Out-Null

Copy-Item "$VcpkgInstalled\lib\*" "$OutputDir\lib\" -Recurse -Force
Copy-Item "$VcpkgInstalled\include\*" "$OutputDir\include\" -Recurse -Force

Write-Host "Done"
