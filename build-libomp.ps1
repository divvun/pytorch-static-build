#
# build-libomp.ps1 - Build LLVM OpenMP runtime as static library (PowerShell)
#
# Usage:
#   .\build-libomp.ps1 -Target x86_64-pc-windows-msvc
#   .\build-libomp.ps1 -Target x86_64-pc-windows-msvc -BuildType Debug
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
    Write-Host "Usage: build-libomp.ps1 -Target <triple> [options]"
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

Write-Host "--- :fire: Building LLVM OpenMP Runtime (libomp)"

# Validate target is Windows
if ($Target -notmatch "windows") {
    Write-Host "Error: This PowerShell script is for Windows targets only" -ForegroundColor Red
    Write-Host "Target: $Target" -ForegroundColor Red
    exit 1
}

Write-Host "Warning: Static OpenMP is not officially supported on Windows but we're building it anyway"

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

# Check for uv and set up Python environment
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "Error: uv is not installed" -ForegroundColor Red
    Write-Host "Install it with: irm https://astral.sh/uv/install.ps1 | iex"
    exit 1
}

if (-not (Test-Path "$RepoRoot\.venv")) {
    Write-Host "+++ :python: Creating Python virtual environment with uv"
    & uv venv
}

Write-Host "+++ :package: Installing Python dependencies with uv"
& uv pip install pyyaml setuptools typing-extensions 2>$null

Write-Host "+++ :snake: Activating Python virtual environment"
& "$RepoRoot\.venv\Scripts\Activate.ps1"

# Check for required tools
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Error: git not found" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Host "Error: cmake not found" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    Write-Host "Error: ninja not found" -ForegroundColor Red
    exit 1
}

# Set up paths
$LLVMProjectDir = Join-Path $RepoRoot "llvm-project"
$BuildRoot = Join-Path $RepoRoot "target\$Target\build\openmp"
$InstallPrefix = Join-Path $RepoRoot "target\$Target\libomp"

# Clone LLVM project if not already present
if (-not (Test-Path $LLVMProjectDir)) {
    Write-Host "+++ :arrow_down: Cloning LLVM project (tag llvmorg-21.1.4)"
    & git clone --depth 1 --branch llvmorg-21.1.4 https://github.com/llvm/llvm-project.git $LLVMProjectDir
} else {
    Write-Host "LLVM project already exists at $LLVMProjectDir"
}

# Verify OpenMP runtime directory exists
if (-not (Test-Path "$LLVMProjectDir\openmp\runtime")) {
    Write-Host "Error: OpenMP runtime not found at $LLVMProjectDir\openmp\runtime" -ForegroundColor Red
    Write-Host "Try deleting llvm-project\ and re-running to clone fresh"
    exit 1
}

# Clean build directory if requested
if ($CleanBuild) {
    Write-Host "+++ :broom: Cleaning build directory"
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
    "-DCMAKE_CXX_STANDARD=17",
    "-DCMAKE_C_COMPILER=cl.exe",
    "-DCMAKE_CXX_COMPILER=cl.exe",
    "-DLIBOMP_ENABLE_SHARED=ON",
    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
    "-DOPENMP_ENABLE_TESTING=OFF",
    "-DLIBOMP_OMPT_SUPPORT=OFF"
)

# Display build configuration
Write-Host ""
Write-Host "+++ :gear: OpenMP Build Configuration"
Write-Host "Target triple:      $Target"
Write-Host "Build type:         $BuildType"
Write-Host "Platform:           windows"
Write-Host "C compiler:         cl.exe"
Write-Host "C++ compiler:       cl.exe"
Write-Host "LLVM source:        $LLVMProjectDir"
Write-Host "Build directory:    $BuildRoot"
Write-Host "Install prefix:     $InstallPrefix"
Write-Host ""

# Run CMake configuration
Write-Host "+++ :cmake: Running CMake configuration"
Push-Location $BuildRoot
try {
    & $CMakePath "$LLVMProjectDir\openmp" @CMakeArgs
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

Write-Host ""
Write-Host "--- :white_check_mark: OpenMP build completed successfully!"
Write-Host ""
Write-Host "Target: $Target"
Write-Host ""
Write-Host "Library files:"
Get-ChildItem "$InstallPrefix\lib\*omp*" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.FullName)" }
Write-Host ""
Write-Host "Header files:"
Get-ChildItem "$InstallPrefix\include\*omp*" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.FullName)" }
Write-Host ""
Write-Host "You can now link against: $InstallPrefix\lib\libomp.lib"
Write-Host ""
