#
# build-windows.ps1 - Build PyTorch C++ libraries on Windows using MSVC (PowerShell)
#
# Usage:
#   .\build-windows.ps1 -Target x86_64-pc-windows-msvc
#   .\build-windows.ps1 -Target i686-pc-windows-msvc -BuildType Debug
#   .\build-windows.ps1 -Target x86_64-pc-windows-msvc -Shared
#

param(
    [Parameter(Mandatory=$true)]
    [string]$Target,

    [ValidateSet("Release","Debug","RelWithDebInfo","MinSizeRel")]
    [string]$BuildType = "Release",

    [switch]$NoClean,
    [switch]$Static,
    [switch]$Shared,
    [switch]$Lite,
    [switch]$Full,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Detect script location and repo root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = $ScriptDir
$PyTorchRoot = Join-Path $RepoRoot "pytorch"

# Parse options
$CleanBuild = -not $NoClean
$BuildSharedLibs = $Shared
$BuildLiteInterpreter = $Lite
$UseOpenMP = $true

# Show help
if ($Help) {
    Write-Host "Usage: build-windows.ps1 -Target <triple> [options]"
    Write-Host ""
    Write-Host "Required:"
    Write-Host "  -Target <triple>     Target triple (x86_64-pc-windows-msvc or i686-pc-windows-msvc)"
    Write-Host ""
    Write-Host "Build Options:"
    Write-Host "  -BuildType <type>    Build type: Release (default), Debug, RelWithDebInfo, MinSizeRel"
    Write-Host "  -NoClean             Skip cleaning build directories"
    Write-Host "  -Static              Build static libraries (default)"
    Write-Host "  -Shared              Build shared libraries"
    Write-Host "  -Lite                Build Lite Interpreter"
    Write-Host "  -Full                Build full interpreter (default)"
    Write-Host "  -Help                Show this help message"
    exit 0
}

Write-Host "--- :fire: Building PyTorch C++ libraries for Windows (MSVC)"

# Validate target is Windows
if ($Target -notmatch "windows") {
    Write-Host "Error: This PowerShell script is for Windows targets only" -ForegroundColor Red
    Write-Host "Target: $Target" -ForegroundColor Red
    exit 1
}

# Determine architecture from target
if ($Target -match "x86_64") {
    $Arch = "x64"
} elseif ($Target -match "i686") {
    $Arch = "x86"
} else {
    Write-Host "Error: Could not determine architecture from target: $Target" -ForegroundColor Red
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

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "Error: uv is not installed" -ForegroundColor Red
    Write-Host "Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
}

# Change to PyTorch directory
if (-not (Test-Path $PyTorchRoot)) {
    Write-Host "Error: PyTorch source not found at $PyTorchRoot" -ForegroundColor Red
    Write-Host "Download PyTorch first with: ./download-cache.sh"
    exit 1
}

Set-Location $PyTorchRoot

# Get Python executable from uv
if (-not (Test-Path ".venv")) {
    Write-Host "+++ :python: Creating Python virtual environment with uv"
    & uv venv
}

$PythonExe = Join-Path (Get-Location) ".venv\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) {
    Write-Host "Error: Python not found at ${PythonExe}" -ForegroundColor Red
    exit 1
}

Write-Host "Using Python: ${PythonExe}"

# Get tool paths
$NinjaPath = (Get-Command ninja).Source
$CMakePath = (Get-Command cmake).Source

# Install minimal Python dependencies
Write-Host "+++ :package: Installing Python dependencies with uv"
& uv pip install pyyaml setuptools typing-extensions 2>$null

# Fetch optional dependencies
if (-not (Test-Path "third_party\eigen\CMakeLists.txt")) {
    Write-Host "+++ :arrow_down: Fetching optional Eigen dependency"
    & $PythonExe tools\optional_submodules.py checkout_eigen
}

# Set up build and install directories
$Caffe2Root = Get-Location
$InstallPrefix = Join-Path $RepoRoot "target\$Target"
$BuildRoot = Join-Path $InstallPrefix "build\pytorch"

if ($CleanBuild) {
    Write-Host "+++ :broom: Cleaning build directory"
    if (Test-Path $BuildRoot) {
        Remove-Item -Recurse -Force $BuildRoot
    }
}

New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null

# Python configuration (needed for CMake generation)
$PythonPrefixPath = & $PythonExe -c 'import sysconfig; print(sysconfig.get_path("purelib"))' | ForEach-Object { $_ -replace '\\', '/' }
$PythonExecutable = & $PythonExe -c 'import sys; print(sys.executable)' | ForEach-Object { $_ -replace '\\', '/' }

# Prepare CMake arguments
$CMakeArgs = @(
    "-DCMAKE_PREFIX_PATH=${InstallPrefix};${PythonPrefixPath}",
    "-DPython_EXECUTABLE=${PythonExecutable}",
    "-GNinja",
    "-DCMAKE_MAKE_PROGRAM=$NinjaPath",
    "-DCMAKE_WARN_DEPRECATED=OFF",
    "-DCMAKE_INSTALL_PREFIX=$InstallPrefix",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DCMAKE_C_COMPILER=cl.exe",
    "-DCMAKE_CXX_COMPILER=cl.exe",
    "-DCMAKE_CXX_STANDARD=17"
)

# MSVC-specific: Use static runtime for static builds
if (-not $BuildSharedLibs) {
    $CMakeArgs += "-DCAFFE2_USE_MSVC_STATIC_RUNTIME=ON"
} else {
    $CMakeArgs += "-DCAFFE2_USE_MSVC_STATIC_RUNTIME=OFF"
}

# MSVC_Z7_OVERRIDE: Use /Zi debug format by default
$CMakeArgs += "-DMSVC_Z7_OVERRIDE=OFF"

# Static or shared libraries
if ($BuildSharedLibs) {
    $CMakeArgs += "-DBUILD_SHARED_LIBS=ON"
} else {
    $CMakeArgs += "-DBUILD_SHARED_LIBS=OFF"
}

# Lite interpreter
if ($BuildLiteInterpreter) {
    $CMakeArgs += "-DBUILD_LITE_INTERPRETER=ON"
    $CMakeArgs += "-DUSE_LITE_INTERPRETER_PROFILER=OFF"
} else {
    $CMakeArgs += "-DBUILD_LITE_INTERPRETER=OFF"
}

# Disable Python bindings and tests
$CMakeArgs += "-DBUILD_PYTHON=OFF"
$CMakeArgs += "-DBUILD_TEST=OFF"
$CMakeArgs += "-DBUILD_BINARY=OFF"

# Windows-specific features
# Check for custom-built OpenMP
$CustomOpenMPLib = Join-Path $InstallPrefix "lib\libomp.a"
$CustomOpenMPInclude = Join-Path $InstallPrefix "include"
if ($UseOpenMP -and (Test-Path $CustomOpenMPLib)) {
    Write-Host "Using custom-built static OpenMP from ${CustomOpenMPLib}"
    $CMakeArgs += "-DUSE_OPENMP=ON"
    $CMakeArgs += "-DOpenMP_C_FLAGS=-Xclang -fopenmp -I${CustomOpenMPInclude}"
    $CMakeArgs += "-DOpenMP_CXX_FLAGS=-Xclang -fopenmp -I${CustomOpenMPInclude}"
    $CMakeArgs += "-DOpenMP_C_LIB_NAMES=omp"
    $CMakeArgs += "-DOpenMP_CXX_LIB_NAMES=omp"
    $CMakeArgs += "-DOpenMP_omp_LIBRARY=${CustomOpenMPLib}"
} elseif ($UseOpenMP) {
    $CMakeArgs += "-DUSE_OPENMP=ON"
} else {
    $CMakeArgs += "-DUSE_OPENMP=OFF"
}

# Distributed training not supported on Windows (TensorPipe limitation)
$CMakeArgs += "-DUSE_DISTRIBUTED=OFF"

# Disable unused dependencies
$CMakeArgs += "-DUSE_CUDA=OFF"
$CMakeArgs += "-DUSE_ITT=OFF"
$CMakeArgs += "-DUSE_GFLAGS=OFF"
$CMakeArgs += "-DUSE_OPENCV=OFF"
$CMakeArgs += "-DUSE_MPI=OFF"
$CMakeArgs += "-DUSE_KINETO=OFF"
$CMakeArgs += "-DUSE_MKLDNN=OFF"
$CMakeArgs += "-DUSE_FBGEMM=OFF"
$CMakeArgs += "-DUSE_PROF=OFF"

# Check for custom-built Protobuf
$CustomProtoc = Join-Path $InstallPrefix "bin\protoc.exe"
$CustomProtobufLib = Join-Path $InstallPrefix "lib\libprotobuf.a"
$CustomProtobufCMakeDir = Join-Path $InstallPrefix "lib\cmake\protobuf"
if ((Test-Path $CustomProtoc) -and (Test-Path $CustomProtobufLib)) {
    Write-Host "Using custom-built static Protobuf from ${CustomProtobufLib}"
    $CMakeArgs += "-DBUILD_CUSTOM_PROTOBUF=OFF"
    $CMakeArgs += "-DCAFFE2_CUSTOM_PROTOC_EXECUTABLE=${CustomProtoc}"
    $CMakeArgs += "-DProtobuf_PROTOC_EXECUTABLE=${CustomProtoc}"
    $CMakeArgs += "-DProtobuf_DIR=${CustomProtobufCMakeDir}"
} else {
    Write-Host "Error: Custom protobuf not found!" -ForegroundColor Red
    Write-Host "Build protobuf first with: .\build-protobuf.ps1 -Target ${Target}"
    exit 1
}

# Performance: use mimalloc allocator
$CMakeArgs += "-DUSE_MIMALLOC=ON"

# Display build configuration
Write-Host ""
Write-Host "+++ :gear: Windows Build Configuration"
Write-Host "Target triple:      $Target"
Write-Host "Build type:         $BuildType"
Write-Host "Library type:       $(if ($BuildSharedLibs) { 'shared' } else { 'static' })"
Write-Host "Architecture:       $Arch"
Write-Host "Python:             $PythonExe"
Write-Host "Output directory:   $BuildRoot"
if (Test-Path $CustomOpenMPLib) {
    Write-Host "OpenMP:             custom static (${CustomOpenMPLib})"
} else {
    Write-Host "OpenMP:             system (USE_OPENMP=${UseOpenMP})"
}
if (Test-Path $CustomProtobufLib) {
    Write-Host "Protobuf:           custom static (${CustomProtobufLib})"
} else {
    Write-Host "Protobuf:           build from source"
}
Write-Host "BUILD_LITE:         ${BuildLiteInterpreter}"
Write-Host "MSVC Static RT:     $(if (-not $BuildSharedLibs) { 'ON' } else { 'OFF' })"
Write-Host ""

# Run CMake configuration
Write-Host "+++ :cmake: Running CMake configuration"
Push-Location $BuildRoot
try {
    & $CMakePath $Caffe2Root @CMakeArgs
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

# Copy all build artifacts to sysroot
Write-Host "+++ :file_folder: Copying libraries and headers to sysroot"
if (Test-Path "$BuildRoot\lib") {
    Copy-Item -Path "$BuildRoot\lib\*" -Destination "$InstallPrefix\lib\" -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$BuildRoot\include") {
    Copy-Item -Path "$BuildRoot\include\*" -Destination "$InstallPrefix\include\" -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "--- :white_check_mark: Windows build completed successfully!"
Write-Host ""
Write-Host "Target: $Target"
Write-Host ""
Write-Host "Library files:"
Write-Host "  $BuildRoot\lib\"
Write-Host ""
Write-Host "Header files:"
Write-Host "  $BuildRoot\include\"
Write-Host ""
