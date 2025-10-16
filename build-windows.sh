#!/bin/bash
#
# build-windows.sh - Build PyTorch C++ libraries on Windows using MSYS2 + MSVC
#
# Usage:
#   ./build-windows.sh              # Build static libraries for x64
#   ./build-windows.sh --arch x86   # Build for x86 (32-bit)
#   ./build-windows.sh --debug      # Build with debug symbols
#   ./build-windows.sh --shared     # Build shared libraries
#
# Requirements:
#   - MSYS2 environment
#   - MSVC build tools (Visual Studio or Build Tools)
#   - cmake, ninja, uv installed in MSYS2
#

set -e

# Detect script location and repo root
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="${SCRIPT_DIR}"
PYTORCH_ROOT="${REPO_ROOT}/pytorch"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default options
BUILD_TYPE="Release"  # Release, Debug, MinSizeRel, RelWithDebInfo
CLEAN_BUILD=1  # Clean by default for reliable builds
BUILD_SHARED_LIBS=0  # Build static libraries by default
USE_OPENMP=1
BUILD_LITE_INTERPRETER=1
VERBOSE=0
ARCH="x64"  # x64 or x86

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --x86)
            ARCH="x86"
            shift
            ;;
        --x64)
            ARCH="x64"
            shift
            ;;
        --no-clean)
            CLEAN_BUILD=0
            shift
            ;;
        --shared)
            BUILD_SHARED_LIBS=1
            shift
            ;;
        --static)
            BUILD_SHARED_LIBS=0
            shift
            ;;
        --debug)
            BUILD_TYPE="Debug"
            shift
            ;;
        --release)
            BUILD_TYPE="Release"
            shift
            ;;
        --relwithdebinfo)
            BUILD_TYPE="RelWithDebInfo"
            shift
            ;;
        --minsize|--minsizerel)
            BUILD_TYPE="MinSizeRel"
            shift
            ;;
        --lite)
            BUILD_LITE_INTERPRETER=1
            shift
            ;;
        --full)
            BUILD_LITE_INTERPRETER=0
            shift
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Architecture Options:"
            echo "  --arch <arch>        Target architecture (x64, x86)"
            echo "  --x64                Build for x64 (default)"
            echo "  --x86                Build for x86 (32-bit)"
            echo ""
            echo "Build Options:"
            echo "  --no-clean           Skip cleaning build directories (cleans by default)"
            echo "  --static             Build static libraries (default)"
            echo "  --shared             Build shared libraries instead of static"
            echo "  --debug              Build with debug symbols"
            echo "  --release            Build optimized release (default)"
            echo "  --relwithdebinfo     Build optimized with debug symbols"
            echo "  --minsize            Build for minimum size"
            echo ""
            echo "Feature Options:"
            echo "  --lite               Build Lite Interpreter (default)"
            echo "  --full               Build full interpreter"
            echo "  --verbose, -v        Verbose output"
            echo "  --help               Show this help message"
            echo ""
            echo "Requirements:"
            echo "  MSYS2 environment with MSVC build tools"
            echo "  cmake, ninja, uv installed in MSYS2"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Validate architecture
if [ "$ARCH" != "x64" ] && [ "$ARCH" != "x86" ]; then
    echo -e "${RED}Error: Invalid architecture: ${ARCH}${NC}"
    echo "Valid architectures: x64, x86"
    exit 1
fi

# Check for uv
if ! command -v uv &> /dev/null; then
    echo -e "${RED}Error: uv is not installed${NC}"
    echo "Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# Check for required tools
if ! command -v ninja &> /dev/null; then
    echo -e "${RED}Error: ninja not found${NC}"
    echo "Install it with: pacman -S mingw-w64-x86_64-ninja"
    exit 1
fi

if ! command -v cmake &> /dev/null; then
    echo -e "${RED}Error: cmake not found${NC}"
    echo "Install it with: pacman -S mingw-w64-x86_64-cmake"
    exit 1
fi

# Check for MSVC (cl.exe should be in PATH)
if ! command -v cl.exe &> /dev/null; then
    echo -e "${RED}Error: MSVC compiler (cl.exe) not found in PATH${NC}"
    echo ""
    echo "Please ensure you have:"
    echo "  1. Visual Studio or Visual Studio Build Tools installed"
    echo "  2. Run this script from a MSYS2 shell with MSVC environment loaded"
    echo "  3. Or manually add MSVC to PATH before running this script"
    echo ""
    echo "Example setup:"
    echo "  # From MSYS2 shell:"
    echo "  export PATH=\"/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/<version>/bin/Hostx64/x64:\$PATH\""
    exit 1
fi

echo -e "${GREEN}Building PyTorch C++ libraries for Windows (MSVC)${NC}"

# Change to PyTorch directory if not already there
if [ "$(pwd)" != "${PYTORCH_ROOT}" ]; then
    cd "${PYTORCH_ROOT}"
fi

# Get Python executable from uv
if [ ! -d ".venv" ]; then
    echo -e "${YELLOW}No .venv found, creating one with uv...${NC}"
    uv venv
fi

PYTHON="$(pwd)/.venv/Scripts/python.exe"
if [ ! -f "$PYTHON" ]; then
    echo -e "${RED}Error: Python not found at ${PYTHON}${NC}"
    exit 1
fi

echo -e "${GREEN}Using Python: ${PYTHON}${NC}"

# Get tool paths
NINJA_PATH=$(which ninja)
CMAKE_PATH=$(which cmake)

# Install minimal Python dependencies
echo -e "${YELLOW}Installing Python dependencies with uv...${NC}"
uv pip install pyyaml setuptools typing-extensions 2>/dev/null || {
    echo -e "${YELLOW}Warning: Some dependencies failed to install${NC}"
}

# Fetch optional dependencies
if [ ! -f "third_party/eigen/CMakeLists.txt" ]; then
    echo -e "${YELLOW}Fetching optional Eigen dependency...${NC}"
    "$PYTHON" tools/optional_submodules.py checkout_eigen
fi

# Determine target triple
if [ "$ARCH" = "x64" ]; then
    TARGET_TRIPLE="x86_64-pc-windows-msvc"
else
    TARGET_TRIPLE="i686-pc-windows-msvc"
fi

# Set up build directory
CAFFE2_ROOT="$(pwd)"
BUILD_ROOT="${BUILD_ROOT:-${REPO_ROOT}/target/${TARGET_TRIPLE}}"
INSTALL_PREFIX="${BUILD_ROOT}"

if [ $CLEAN_BUILD -eq 1 ]; then
    echo -e "${YELLOW}Cleaning build directory...${NC}"
    rm -rf "${BUILD_ROOT}"
fi

mkdir -p "${BUILD_ROOT}"

# Prepare CMake arguments
CMAKE_ARGS=()

# Python configuration (needed for CMake generation)
# Note: On Windows, we need to use Windows-style paths for Python
PYTHON_PREFIX_PATH=$($PYTHON -c 'import sysconfig; print(sysconfig.get_path("purelib"))' | sed 's|\\|/|g')
PYTHON_EXECUTABLE=$($PYTHON -c 'import sys; print(sys.executable)' | sed 's|\\|/|g')

CMAKE_ARGS+=("-DCMAKE_PREFIX_PATH=${PYTHON_PREFIX_PATH}")
CMAKE_ARGS+=("-DPython_EXECUTABLE=${PYTHON_EXECUTABLE}")

# Use Ninja
CMAKE_ARGS+=("-GNinja")
CMAKE_ARGS+=("-DCMAKE_MAKE_PROGRAM=${NINJA_PATH}")

# Suppress CMake deprecation warnings
CMAKE_ARGS+=("-DCMAKE_WARN_DEPRECATED=OFF")

# Build configuration
CMAKE_ARGS+=("-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}")
CMAKE_ARGS+=("-DCMAKE_BUILD_TYPE=${BUILD_TYPE}")

# MSVC-specific: Use static runtime for static builds
if [ $BUILD_SHARED_LIBS -eq 0 ]; then
    CMAKE_ARGS+=("-DCAFFE2_USE_MSVC_STATIC_RUNTIME=ON")
else
    CMAKE_ARGS+=("-DCAFFE2_USE_MSVC_STATIC_RUNTIME=OFF")
fi

# MSVC_Z7_OVERRIDE: Use /Zi debug format by default
CMAKE_ARGS+=("-DMSVC_Z7_OVERRIDE=OFF")

# Static or shared libraries
if [ $BUILD_SHARED_LIBS -eq 1 ]; then
    CMAKE_ARGS+=("-DBUILD_SHARED_LIBS=ON")
else
    CMAKE_ARGS+=("-DBUILD_SHARED_LIBS=OFF")
fi

# Lite interpreter
if [ $BUILD_LITE_INTERPRETER -eq 1 ]; then
    CMAKE_ARGS+=("-DBUILD_LITE_INTERPRETER=ON")
    CMAKE_ARGS+=("-DUSE_LITE_INTERPRETER_PROFILER=OFF")
else
    CMAKE_ARGS+=("-DBUILD_LITE_INTERPRETER=OFF")
fi

# Disable Python bindings and tests
CMAKE_ARGS+=("-DBUILD_PYTHON=OFF")
CMAKE_ARGS+=("-DBUILD_TEST=OFF")
CMAKE_ARGS+=("-DBUILD_BINARY=OFF")

# Windows-specific features
if [ $USE_OPENMP -eq 1 ]; then
    CMAKE_ARGS+=("-DUSE_OPENMP=ON")
else
    CMAKE_ARGS+=("-DUSE_OPENMP=OFF")
fi

# Distributed training not supported on Windows (TensorPipe limitation)
CMAKE_ARGS+=("-DUSE_DISTRIBUTED=OFF")

# Disable unused dependencies
CMAKE_ARGS+=("-DUSE_CUDA=OFF")
CMAKE_ARGS+=("-DUSE_ITT=OFF")
CMAKE_ARGS+=("-DUSE_GFLAGS=OFF")
CMAKE_ARGS+=("-DUSE_OPENCV=OFF")
CMAKE_ARGS+=("-DUSE_MPI=OFF")
CMAKE_ARGS+=("-DUSE_KINETO=OFF")
CMAKE_ARGS+=("-DUSE_MKLDNN=OFF")
CMAKE_ARGS+=("-DUSE_PROF=OFF")
CMAKE_ARGS+=("-DBUILD_CUSTOM_PROTOBUF=OFF")

# Performance: use mimalloc allocator
CMAKE_ARGS+=("-DUSE_MIMALLOC=ON")

# Verbose
if [ $VERBOSE -eq 1 ]; then
    CMAKE_ARGS+=("-DCMAKE_VERBOSE_MAKEFILE=1")
fi

# Display build configuration
echo ""
echo -e "${GREEN}=== Windows Build Configuration ===${NC}"
echo "Target triple:      ${TARGET_TRIPLE}"
echo "Build type:         ${BUILD_TYPE}"
echo "Library type:       $([ ${BUILD_SHARED_LIBS} -eq 1 ] && echo 'shared' || echo 'static')"
echo "Architecture:       ${ARCH}"
echo "Python:             ${PYTHON}"
echo "Output directory:   ${BUILD_ROOT}"
echo "USE_OPENMP:         ${USE_OPENMP}"
echo "BUILD_LITE:         ${BUILD_LITE_INTERPRETER}"
echo "MSVC Static RT:     $([ ${BUILD_SHARED_LIBS} -eq 0 ] && echo 'ON' || echo 'OFF')"
echo -e "${GREEN}====================================${NC}"
echo ""

# Run CMake configuration
echo -e "${YELLOW}Running CMake configuration...${NC}"
cd "${BUILD_ROOT}"
"${CMAKE_PATH}" "${CAFFE2_ROOT}" "${CMAKE_ARGS[@]}"

# Determine number of parallel jobs
if [ -z "$MAX_JOBS" ]; then
    MAX_JOBS=$(nproc)
fi

# Build
echo -e "${YELLOW}Building with ${MAX_JOBS} parallel jobs...${NC}"
"${CMAKE_PATH}" --build . --target install -- "-j${MAX_JOBS}"

echo ""
echo -e "${GREEN}Windows build completed successfully!${NC}"
echo ""
echo "Target: ${TARGET_TRIPLE}"
echo ""
echo "Library files:"
echo "  ${BUILD_ROOT}/lib/"
echo ""
echo "Header files:"
echo "  ${BUILD_ROOT}/include/"
echo ""
