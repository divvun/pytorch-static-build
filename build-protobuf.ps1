#
# build-protobuf.ps1 - Build Protocol Buffers as static library from official repository (Windows/PowerShell)
#
# Usage:
#   .\build-protobuf.ps1 -Target x86_64-pc-windows-msvc
#   .\build-protobuf.ps1 -Target x86_64-pc-windows-msvc -BuildType Debug
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
    Write-Host "Usage: build-protobuf.ps1 -Target <triple> [options]"
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

Write-Host "--- :hammer: Building Protocol Buffers (libprotobuf)"

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

# Add Windows SDK tools to PATH (rc.exe, mt.exe)
$WindowsKitsPath = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
if (Test-Path $WindowsKitsPath) {
    $SDKVersion = Get-ChildItem $WindowsKitsPath |
        Where-Object { $_.PSIsContainer -and $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($SDKVersion) {
        $SDKBin = Join-Path $WindowsKitsPath "$($SDKVersion.Name)\x64"
        if (Test-Path $SDKBin) {
            Write-Host "Found Windows SDK at: $SDKBin"
            $env:PATH = "$SDKBin;$env:PATH"
        }
    }
}

# Add Windows SDK libraries to LIB path
$WindowsKitsLibPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Lib"
if (Test-Path $WindowsKitsLibPath) {
    $SDKVersion = Get-ChildItem $WindowsKitsLibPath |
        Where-Object { $_.PSIsContainer -and $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($SDKVersion) {
        $SDKLibUm = Join-Path $WindowsKitsLibPath "$($SDKVersion.Name)\um\x64"
        $SDKLibUcrt = Join-Path $WindowsKitsLibPath "$($SDKVersion.Name)\ucrt\x64"
        if ((Test-Path $SDKLibUm) -and (Test-Path $SDKLibUcrt)) {
            $env:LIB = "$SDKLibUm;$SDKLibUcrt;$env:LIB"
            Write-Host "Added Windows SDK libraries to LIB"
        }
    }
}

# Add Windows SDK include paths
$WindowsKitsIncludePath = "${env:ProgramFiles(x86)}\Windows Kits\10\Include"
if (Test-Path $WindowsKitsIncludePath) {
    $SDKVersion = Get-ChildItem $WindowsKitsIncludePath |
        Where-Object { $_.PSIsContainer -and $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($SDKVersion) {
        $SDKIncUcrt = Join-Path $WindowsKitsIncludePath "$($SDKVersion.Name)\ucrt"
        $SDKIncShared = Join-Path $WindowsKitsIncludePath "$($SDKVersion.Name)\shared"
        $SDKIncUm = Join-Path $WindowsKitsIncludePath "$($SDKVersion.Name)\um"
        if (Test-Path $SDKIncUcrt) {
            $env:INCLUDE = "$SDKIncUcrt;$SDKIncShared;$SDKIncUm;$env:INCLUDE"
            Write-Host "Added Windows SDK includes to INCLUDE"
        }
    }
}

# Debug: Print PATH
Write-Host "PATH: $env:PATH"

# Check for required tools
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Error: git not found" -ForegroundColor Red
    Write-Host "Install it from https://git-scm.com/"
    exit 1
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Host "Error: cmake not found" -ForegroundColor Red
    Write-Host "Install it from https://cmake.org/"
    exit 1
}

if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    Write-Host "Error: ninja not found" -ForegroundColor Red
    Write-Host "Install it with: pacman -S ninja"
    exit 1
}

# Set up paths
$ProtobufSourceDir = Join-Path $RepoRoot "protobuf"
$BuildRoot = Join-Path $RepoRoot "target\$Target\build\protobuf"
$InstallPrefix = Join-Path $RepoRoot "target\$Target"

# Clone protobuf if not already present
if (-not (Test-Path $ProtobufSourceDir)) {
    Write-Host "Cloning Protocol Buffers from GitHub..." -ForegroundColor Yellow
    & git clone --depth 1 --branch main https://github.com/protocolbuffers/protobuf.git $ProtobufSourceDir
}
else {
    Write-Host "Using existing Protocol Buffers source at $ProtobufSourceDir" -ForegroundColor Green
}

# Verify protobuf CMakeLists.txt exists
if (-not (Test-Path "$ProtobufSourceDir\CMakeLists.txt")) {
    Write-Host "Error: Protobuf CMakeLists.txt not found at $ProtobufSourceDir\CMakeLists.txt" -ForegroundColor Red
    Write-Host "The protobuf clone might be incomplete or corrupted. Try removing $ProtobufSourceDir and running again."
    exit 1
}

# Clean build directory if requested
if ($CleanBuild) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    if (Test-Path $BuildRoot) {
        Remove-Item -Recurse -Force $BuildRoot
    }
}

New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null

# Get tool paths
$NinjaPath = (Get-Command ninja).Source
$CMakePath = (Get-Command cmake).Source

# Prepare CMake arguments
$CMakeArgs = @(
    "-GNinja",
    "-DCMAKE_MAKE_PROGRAM=$NinjaPath",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DCMAKE_INSTALL_PREFIX=$InstallPrefix",
    "-DCMAKE_C_COMPILER=cl.exe",
    "-DCMAKE_CXX_COMPILER=cl.exe",
    "-DCMAKE_CXX_STANDARD=17",
    "-Dprotobuf_BUILD_SHARED_LIBS=OFF",
    "-Dprotobuf_FORCE_FETCH_DEPENDENCIES=ON",
    "-DABSL_ENABLE_INSTALL=ON",
    "-DABSL_PROPAGATE_CXX_STD=ON",
    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
    "-Dprotobuf_BUILD_TESTS=OFF",
    "-Dprotobuf_BUILD_EXAMPLES=OFF",
    "-Dprotobuf_BUILD_PROTOC_BINARIES=ON"
)

# Display build configuration
Write-Host ""
Write-Host "+++ :gear: Protobuf Build Configuration"
Write-Host "Target triple:      $Target"
Write-Host "Build type:         $BuildType"
Write-Host "Platform:           windows"
Write-Host "C compiler:         cl.exe"
Write-Host "C++ compiler:       cl.exe"
Write-Host "Protobuf source:    $ProtobufSourceDir"
Write-Host "Build directory:    $BuildRoot"
Write-Host "Install prefix:     $InstallPrefix"
Write-Host ""

# Run CMake configuration
Write-Host "+++ :cmake: Running CMake configuration"
Push-Location $BuildRoot
try {
    & $CMakePath $ProtobufSourceDir @CMakeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed"
    }
}
finally {
    Pop-Location
}

# Determine number of parallel jobs
$MaxJobs = if ($env:MAX_JOBS) { $env:MAX_JOBS } else { $env:NUMBER_OF_PROCESSORS }

# Build
Write-Host "+++ :package: Building with $MaxJobs parallel jobs"
Push-Location $BuildRoot
try {
    & $CMakePath --build . --target install -- "-j$MaxJobs"
    if ($LASTEXITCODE -ne 0) {
        throw "CMake build failed"
    }
}
finally {
    Pop-Location
}

# Copy Abseil libraries to sysroot (protobuf depends on Abseil)
Write-Host "+++ :file_folder: Copying Abseil libraries to sysroot"
$AbseilLibs = Get-ChildItem -Path $BuildRoot -Filter "libabsl_*.a" -Recurse -ErrorAction SilentlyContinue
if ($AbseilLibs) {
    foreach ($lib in $AbseilLibs) {
        Copy-Item $lib.FullName -Destination "$InstallPrefix\lib\" -Force
    }
    Write-Host "Copied $($AbseilLibs.Count) Abseil libraries"
}
else {
    Write-Host "Warning: No Abseil libraries found in build directory"
}

# Copy Abseil headers if present
$AbseilHeaderSrc = @(
    "$BuildRoot\abseil-cpp\absl",
    "$BuildRoot\_deps\abseil-cpp-src\absl"
)
foreach ($src in $AbseilHeaderSrc) {
    if (Test-Path $src) {
        Write-Host "Copying Abseil headers"
        Copy-Item -Path $src -Destination "$InstallPrefix\include\" -Recurse -Force -ErrorAction SilentlyContinue
        break
    }
}

Write-Host ""
Write-Host "--- :white_check_mark: Protobuf build completed successfully!"
Write-Host ""
Write-Host "Target: $Target"
Write-Host ""
Write-Host "Binaries:"
Get-ChildItem "$InstallPrefix\bin\protoc*" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.FullName)" }
Write-Host ""
Write-Host "Library files:"
Get-ChildItem "$InstallPrefix\lib\libproto*" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.FullName)" }
Write-Host ""
Write-Host "Abseil libraries:"
Get-ChildItem "$InstallPrefix\lib\libabsl_*.a" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.FullName)" }
Write-Host ""
Write-Host "Header files:"
if (Test-Path "$InstallPrefix\include\google\protobuf") {
    Write-Host "  $InstallPrefix\include\google\protobuf"
}
if (Test-Path "$InstallPrefix\include\absl") {
    Write-Host "  $InstallPrefix\include\absl"
}
Write-Host ""
