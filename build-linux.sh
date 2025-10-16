#!/bin/bash
#
# build-linux.sh - Build PyTorch C++ libraries on Linux using uv for Python environment management
#
# Usage:
#   ./build-linux.sh              # Build static libraries
#   ./build-linux.sh --debug      # Build with debug symbols
#   ./build-linux.sh --no-clean   # Skip cleaning build directory
#   ./build-linux.sh --shared     # Build shared libraries
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
USE_DISTRIBUTED=1  # Enable distributed by default on Linux
USE_OPENMP=1
BUILD_LITE_INTERPRETER=1
VERBOSE=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
        --distributed)
            USE_DISTRIBUTED=1
            shift
            ;;
        --no-distributed)
            USE_DISTRIBUTED=0
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
            echo "Build Options:"
            echo "  --no-clean           Skip cleaning build directories (cleans by default)"
            echo "  --static             Build static libraries (default)"
            echo "  --shared             Build shared libraries instead of static"
            echo "  --debug              Build with debug symbols (-O0 -g)"
            echo "  --release            Build optimized release (default)"
            echo "  --relwithdebinfo     Build optimized with debug symbols (-O2 -g)"
            echo "  --minsize            Build for minimum size"
            echo ""
            echo "Feature Options:"
            echo "  --distributed        Enable distributed training support (default)"
            echo "  --no-distributed     Disable distributed training support"
            echo "  --lite               Build Lite Interpreter (default)"
            echo "  --full               Build full interpreter"
            echo "  --verbose, -v        Verbose output"
            echo "  --help               Show this help message"
            echo ""
            echo "Requirements:"
            echo "  clang, clang++, cmake, ninja, protoc, uv"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Check for uv
if ! command -v uv &> /dev/null; then
    echo -e "${RED}Error: uv is not installed${NC}"
    echo "Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# Check for required tools
if ! command -v clang &> /dev/null; then
    echo -e "${RED}Error: clang not found${NC}"
    echo "Install it with your package manager (e.g., apt install clang)"
    exit 1
fi

if ! command -v clang++ &> /dev/null; then
    echo -e "${RED}Error: clang++ not found${NC}"
    echo "Install it with your package manager (e.g., apt install clang)"
    exit 1
fi

if ! command -v ninja &> /dev/null; then
    echo -e "${RED}Error: ninja not found${NC}"
    echo "Install it with your package manager (e.g., apt install ninja-build)"
    exit 1
fi

if ! command -v cmake &> /dev/null; then
    echo -e "${RED}Error: cmake not found${NC}"
    echo "Install it with your package manager (e.g., apt install cmake)"
    exit 1
fi

if ! command -v protoc &> /dev/null; then
    echo -e "${RED}Error: protoc not found${NC}"
    echo "Install it with your package manager (e.g., apt install protobuf-compiler)"
    exit 1
fi

echo -e "${GREEN}Building PyTorch C++ libraries for Linux${NC}"

# Change to PyTorch directory if not already there
if [ "$(pwd)" != "${PYTORCH_ROOT}" ]; then
    cd "${PYTORCH_ROOT}"
fi

# Detect architecture
ARCH=$(uname -m)
echo -e "${GREEN}Detected architecture: ${ARCH}${NC}"

# Get Python executable from uv
if [ ! -d ".venv" ]; then
    echo -e "${YELLOW}No .venv found, creating one with uv...${NC}"
    uv venv
fi

PYTHON="$(pwd)/.venv/bin/python"
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
if [ "${ARCH}" = "x86_64" ]; then
    TARGET_TRIPLE="x86_64-unknown-linux-gnu"
elif [ "${ARCH}" = "aarch64" ]; then
    TARGET_TRIPLE="aarch64-unknown-linux-gnu"
else
    echo -e "${RED}Error: Unsupported architecture: ${ARCH}${NC}"
    exit 1
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

# Set up environment variables
export CC=clang
export CXX=clang++

# Prepare CMake arguments
CMAKE_ARGS=()

# Python configuration (needed for CMake generation)
CMAKE_ARGS+=("-DCMAKE_PREFIX_PATH=$($PYTHON -c 'import sysconfig; print(sysconfig.get_path("purelib"))')")
CMAKE_ARGS+=("-DPython_EXECUTABLE=$($PYTHON -c 'import sys; print(sys.executable)')")

# Use Ninja
CMAKE_ARGS+=("-GNinja")
CMAKE_ARGS+=("-DCMAKE_MAKE_PROGRAM=${NINJA_PATH}")

# Suppress CMake deprecation warnings
CMAKE_ARGS+=("-DCMAKE_WARN_DEPRECATED=OFF")

# Build configuration
CMAKE_ARGS+=("-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}")
CMAKE_ARGS+=("-DCMAKE_BUILD_TYPE=${BUILD_TYPE}")

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

# Linux-specific features
if [ $USE_OPENMP -eq 1 ]; then
    CMAKE_ARGS+=("-DUSE_OPENMP=ON")
else
    CMAKE_ARGS+=("-DUSE_OPENMP=OFF")
fi

if [ $USE_DISTRIBUTED -eq 1 ]; then
    CMAKE_ARGS+=("-DUSE_DISTRIBUTED=ON")
else
    CMAKE_ARGS+=("-DUSE_DISTRIBUTED=OFF")
fi

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
echo -e "${GREEN}=== Linux Build Configuration ===${NC}"
echo "Target triple:      ${TARGET_TRIPLE}"
echo "Build type:         ${BUILD_TYPE}"
echo "Library type:       $([ ${BUILD_SHARED_LIBS} -eq 1 ] && echo 'shared' || echo 'static')"
echo "Architecture:       ${ARCH}"
echo "Python:             ${PYTHON}"
echo "Output directory:   ${BUILD_ROOT}"
echo "USE_DISTRIBUTED:    ${USE_DISTRIBUTED}"
echo "USE_OPENMP:         ${USE_OPENMP}"
echo "BUILD_LITE:         ${BUILD_LITE_INTERPRETER}"
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
echo -e "${GREEN}Linux build completed successfully!${NC}"
echo ""
echo "Target: ${TARGET_TRIPLE}"
echo ""
echo "Library files:"
echo "  ${BUILD_ROOT}/lib/"
echo ""
echo "Header files:"
echo "  ${BUILD_ROOT}/include/"
echo ""
