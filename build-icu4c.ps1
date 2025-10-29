#
# build-icu4c.ps1 - Build ICU4C (International Components for Unicode) on Windows
#
# Usage:
#   .\build-icu4c.ps1 -Target x86_64-pc-windows-msvc
#   .\build-icu4c.ps1 -Target x86_64-pc-windows-msvc -BuildType Debug
#

param(
    [Parameter(Mandatory=$true)]
    [string]$Target,

    [ValidateSet("Release","Debug","RelWithDebInfo","MinSizeRel")]
    [string]$BuildType = "Release",

    [switch]$NoClean,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Detect script location and repo root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = $ScriptDir

# Parse options
$CleanBuild = -not $NoClean

# Show help
if ($Help) {
    Write-Host "Usage: build-icu4c.ps1 -Target <triple> [options]"
    Write-Host ""
    Write-Host "Required:"
    Write-Host "  -Target <triple>     Target triple (e.g., x86_64-pc-windows-msvc)"
    Write-Host ""
    Write-Host "Build Options:"
    Write-Host "  -BuildType <type>    Build type: Release (default), Debug, RelWithDebInfo, MinSizeRel"
    Write-Host "  -NoClean             Skip cleaning build directories"
    Write-Host "  -Help                Show this help message"
    exit 0
}

Write-Host "--- :globe_with_meridians: Building ICU4C (International Components for Unicode)"

# Validate target is Windows
if ($Target -notmatch "windows") {
    Write-Host "Error: This PowerShell script is for Windows targets only" -ForegroundColor Red
    Write-Host "Target: $Target" -ForegroundColor Red
    exit 1
}

# Auto-detect and add MSVC to PATH
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    $VSPaths = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\VC\Tools\MSVC"
    )

    $MSVCFound = $false
    foreach ($VSBase in $VSPaths) {
        if (Test-Path $VSBase) {
            $MSVCVersion = Get-ChildItem $VSBase | Sort-Object Name -Descending | Select-Object -First 1
            if ($MSVCVersion) {
                $MSVCBin = Join-Path $VSBase $MSVCVersion.Name "bin\Hostx64\x64"
                if (Test-Path "$MSVCBin\cl.exe") {
                    Write-Host "Found MSVC at: $MSVCBin"
                    $env:PATH = "$MSVCBin;$env:PATH"

                    # Add MSVC libraries to LIB path
                    $MSVCLibPath = Join-Path $VSBase $MSVCVersion.Name "lib\x64"
                    if (Test-Path $MSVCLibPath) {
                        $env:LIB = "$MSVCLibPath;$env:LIB"
                        Write-Host "Added MSVC libraries to LIB"
                    }

                    # Add MSVC include paths
                    $MSVCIncludePath = Join-Path $VSBase $MSVCVersion.Name "include"
                    if (Test-Path $MSVCIncludePath) {
                        $env:INCLUDE = "$MSVCIncludePath;$env:INCLUDE"
                        Write-Host "Added MSVC includes to INCLUDE"
                    }

                    $MSVCFound = $true
                    break
                }
            }
        }
    }

    if (-not $MSVCFound) {
        Write-Host "Error: Could not locate MSVC automatically" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please ensure you have Visual Studio 2022 or 2019 installed with C++ build tools"
        exit 1
    }
}

# Also add Windows SDK to environment
$SDKPaths = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10"
)

foreach ($SDKBase in $SDKPaths) {
    if (Test-Path $SDKBase) {
        # Find latest SDK version
        $SDKInclude = Join-Path $SDKBase "Include"
        if (Test-Path $SDKInclude) {
            $SDKVersion = Get-ChildItem $SDKInclude | Where-Object { $_.Name -match '^\d+\.' } | Sort-Object Name -Descending | Select-Object -First 1
            if ($SDKVersion) {
                $SDKIncludePath = Join-Path $SDKInclude $SDKVersion.Name
                $env:INCLUDE = "$SDKIncludePath\ucrt;$SDKIncludePath\um;$SDKIncludePath\shared;$env:INCLUDE"

                $SDKLib = Join-Path $SDKBase "Lib" $SDKVersion.Name
                $env:LIB = "$SDKLib\ucrt\x64;$SDKLib\um\x64;$env:LIB"

                Write-Host "Added Windows SDK $($SDKVersion.Name) to environment"
                break
            }
        }
    }
}

# Auto-detect and add MSBuild to PATH
if (-not (Get-Command msbuild.exe -ErrorAction SilentlyContinue)) {
    $MSBuildPaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin"
    )

    $MSBuildFound = $false
    foreach ($MSBuildPath in $MSBuildPaths) {
        if (Test-Path "$MSBuildPath\msbuild.exe") {
            Write-Host "Found MSBuild at: $MSBuildPath"
            $env:PATH = "$MSBuildPath;$env:PATH"
            $MSBuildFound = $true
            break
        }
    }

    if (-not $MSBuildFound) {
        Write-Host "Error: Could not locate MSBuild automatically" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please ensure you have Visual Studio 2022 or 2019 installed with MSBuild"
        exit 1
    }
}

# Set up paths
$ICURoot = Join-Path $RepoRoot "icu"
$ICUSourceDir = Join-Path $ICURoot "icu4c\source"
$ICUSolution = Join-Path $ICUSourceDir "allinone\allinone.sln"
$InstallPrefix = Join-Path $RepoRoot "target\$Target\icu4c"

# Clone ICU if not already present
if (-not (Test-Path $ICURoot)) {
    Write-Host "Cloning ICU from GitHub..." -ForegroundColor Yellow
    & git clone --depth 1 https://github.com/unicode-org/icu.git $ICURoot
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to clone ICU repository" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Using existing ICU source at $ICURoot" -ForegroundColor Green
}

# Verify ICU solution file exists
if (-not (Test-Path $ICUSolution)) {
    Write-Host "Error: ICU solution file not found at $ICUSolution" -ForegroundColor Red
    Write-Host "The ICU clone might be incomplete or corrupted. Try removing $ICURoot and running again."
    exit 1
}

# Clean build directory if requested
$BuildRoot = Join-Path $RepoRoot "target\$Target\build\icu"
if ($CleanBuild -and (Test-Path $BuildRoot)) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $BuildRoot
}

# Create install directory
New-Item -ItemType Directory -Force -Path $InstallPrefix | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallPrefix "bin") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallPrefix "lib") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallPrefix "include") | Out-Null

# Display build configuration
Write-Host ""
Write-Host "=== ICU4C Build Configuration ===" -ForegroundColor Green
Write-Host "Target:           $Target"
Write-Host "Build type:       $BuildType"
Write-Host "Solution:         $ICUSolution"
Write-Host "Install prefix:   $InstallPrefix"
Write-Host "====================================" -ForegroundColor Green
Write-Host ""

# Patch project files to build static libraries instead of DLLs
Write-Host "Patching ICU project files for static library build..." -ForegroundColor Yellow

$ProjectFiles = Get-ChildItem -Path $ICUSourceDir -Filter "*.vcxproj" -Recurse

foreach ($ProjectFile in $ProjectFiles) {
    Write-Host "  Patching $($ProjectFile.Name)"
    $Content = Get-Content $ProjectFile.FullName -Raw

    # Replace DynamicLibrary with StaticLibrary
    $Content = $Content -replace '<ConfigurationType>DynamicLibrary</ConfigurationType>', '<ConfigurationType>StaticLibrary</ConfigurationType>'

    # Write back
    Set-Content -Path $ProjectFile.FullName -Value $Content -NoNewline
}

Write-Host "Patched $($ProjectFiles.Count) project files" -ForegroundColor Green
Write-Host ""

# Change to source directory for build
Push-Location $ICUSourceDir

try {
    # Run MSBuild
    Write-Host "Running MSBuild..." -ForegroundColor Yellow
    $Platform = "x64"
    $SkipUWP = "true"

    Push-Location .\allinone

    & msbuild stubdata\stubdata.vcxproj /p:Configuration=$BuildType /p:Platform=$Platform /p:SkipUWP=$SkipUWP /p:PreprocessorDefinitions="U_STATIC_IMPLEMENTATION=1" /m
    & msbuild common\common.vcxproj /p:Configuration=$BuildType /p:Platform=$Platform /p:SkipUWP=$SkipUWP /p:PreprocessorDefinitions="U_STATIC_IMPLEMENTATION=1" /m
    & msbuild i18n\i18n.vcxproj /p:Configuration=$BuildType /p:Platform=$Platform /p:SkipUWP=$SkipUWP /p:PreprocessorDefinitions="U_STATIC_IMPLEMENTATION=1" /m
    & msbuild io\io.vcxproj /p:Configuration=$BuildType /p:Platform=$Platform /p:SkipUWP=$SkipUWP /p:PreprocessorDefinitions="U_STATIC_IMPLEMENTATION=1" /m
    
    Pop-Location

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: MSBuild failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }

    # Copy built files to install prefix
    Write-Host "Copying build outputs to install prefix..." -ForegroundColor Yellow

    # The build outputs are in bin64 and lib64 directories
    $BinDir = Join-Path $ICUSourceDir "bin64"
    $LibDir = Join-Path $ICUSourceDir "lib64"

    if (Test-Path $BinDir) {
        Copy-Item "$BinDir\*" (Join-Path $InstallPrefix "bin") -Recurse -Force
        Write-Host "Copied binaries from $BinDir"
    }

    if (Test-Path $LibDir) {
        Copy-Item "$LibDir\*" (Join-Path $InstallPrefix "lib") -Recurse -Force
        Write-Host "Copied libraries from $LibDir"
    }

    # Copy include files
    $IncludeDir = Join-Path $ICUSourceDir "common\unicode"
    if (Test-Path $IncludeDir) {
        $TargetInclude = Join-Path $InstallPrefix "include\unicode"
        New-Item -ItemType Directory -Force -Path $TargetInclude | Out-Null
        Copy-Item "$IncludeDir\*" $TargetInclude -Recurse -Force
        Write-Host "Copied headers from $IncludeDir"
    }

    Write-Host ""
    Write-Host "ICU4C build completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Install prefix: $InstallPrefix"
    Write-Host "  Binaries: $InstallPrefix\bin"
    Write-Host "  Libraries: $InstallPrefix\lib"
    Write-Host "  Headers: $InstallPrefix\include"
    Write-Host ""

} finally {
    Pop-Location
}
