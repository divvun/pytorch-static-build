#!/bin/bash
#
# build-ios.sh - Build PyTorch for iOS using uv for Python environment management
#
# Usage:
#   ./build-ios.sh                    # Build for iOS device (arm64)
#   ./build-ios.sh --simulator        # Build for iOS simulator
#   ./build-ios.sh --simulator-arm64  # Build for iOS simulator on Apple Silicon
#   ./build-ios.sh --watchos          # Build for watchOS
#   ./build-ios.sh --debug            # Build with debug symbols
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
IOS_PLATFORM="OS"  # OS (device), SIMULATOR, WATCHOS
IOS_ARCH=""        # Empty = auto-detect based on platform
BUILD_TYPE="MinSizeRel"  # MinSizeRel, Release, Debug, RelWithDebInfo
CLEAN_BUILD=1
USE_PYTORCH_METAL=1
USE_COREML_DELEGATE=0
BUILD_LITE_INTERPRETER=0
ENABLE_BITCODE=0
VERBOSE=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --simulator)
            IOS_PLATFORM="SIMULATOR"
            IOS_ARCH="x86_64"
            shift
            ;;
        --simulator-arm64)
            IOS_PLATFORM="SIMULATOR"
            IOS_ARCH="arm64"
            shift
            ;;
        --device|--os)
            IOS_PLATFORM="OS"
            IOS_ARCH="arm64"
            shift
            ;;
        --watchos)
            IOS_PLATFORM="WATCHOS"
            ENABLE_BITCODE=1
            shift
            ;;
        --no-clean)
            CLEAN_BUILD=0
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
        --metal)
            USE_PYTORCH_METAL=1
            shift
            ;;
        --no-metal)
            USE_PYTORCH_METAL=0
            shift
            ;;
        --coreml)
            USE_COREML_DELEGATE=1
            shift
            ;;
        --bitcode)
            ENABLE_BITCODE=1
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
            echo "Platform Options:"
            echo "  --device             Build for iOS device (arm64) - default"
            echo "  --simulator          Build for iOS simulator (x86_64)"
            echo "  --simulator-arm64    Build for iOS simulator on Apple Silicon"
            echo "  --watchos            Build for watchOS"
            echo ""
            echo "Build Options:"
            echo "  --no-clean           Skip cleaning build directory (cleans by default)"
            echo "  --debug              Build with debug symbols (-O0 -g)"
            echo "  --release            Build optimized release (-O3)"
            echo "  --relwithdebinfo     Build optimized with debug symbols (-O2 -g)"
            echo "  --minsize            Build for minimum size (default)"
            echo ""
            echo "Feature Options:"
            echo "  --metal              Enable Metal support (default)"
            echo "  --no-metal           Disable Metal support"
            echo "  --coreml             Enable Core ML delegate"
            echo "  --bitcode            Enable bitcode embedding"
            echo "  --lite               Build Lite Interpreter"
            echo "  --full               Build full interpreter (default)"
            echo "  --verbose, -v        Verbose output"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Auto-detect architecture if not set
if [ -z "$IOS_ARCH" ]; then
    if [ "$IOS_PLATFORM" = "OS" ]; then
        IOS_ARCH="arm64"
    elif [ "$IOS_PLATFORM" = "SIMULATOR" ]; then
        # Use arm64 if building on Apple Silicon, x86_64 otherwise
        HOST_ARCH=$(uname -m)
        if [ "$HOST_ARCH" = "arm64" ]; then
            IOS_ARCH="arm64"
        else
            IOS_ARCH="x86_64"
        fi
    elif [ "$IOS_PLATFORM" = "WATCHOS" ]; then
        IOS_ARCH="arm64_32"
    fi
fi

# Check for uv
if ! command -v uv &> /dev/null; then
    echo -e "${RED}Error: uv is not installed${NC}"
    echo "Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

echo -e "${GREEN}Building PyTorch for iOS${NC}"

# Change to PyTorch directory if not already there
if [ "$(pwd)" != "${PYTORCH_ROOT}" ]; then
    cd "${PYTORCH_ROOT}"
fi

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

# Check for ninja and cmake (use homebrew versions)
HOST_ARCH=$(uname -m)
if [ "${HOST_ARCH}" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

NINJA_PATH="${BREW_PREFIX}/bin/ninja"
CMAKE_PATH="${BREW_PREFIX}/bin/cmake"

if [ ! -f "${NINJA_PATH}" ]; then
    echo -e "${RED}Error: ninja not found at ${NINJA_PATH}${NC}"
    echo "Install it with: brew install ninja"
    exit 1
fi

if [ ! -f "${CMAKE_PATH}" ]; then
    echo -e "${RED}Error: cmake not found at ${CMAKE_PATH}${NC}"
    echo "Install it with: brew install cmake"
    exit 1
fi

# Tell CMake where to find Ninja (required when using toolchain files)
export CMAKE_MAKE_PROGRAM="${NINJA_PATH}"

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
if [ "$IOS_PLATFORM" = "OS" ]; then
    TARGET_TRIPLE="aarch64-apple-ios"
elif [ "$IOS_PLATFORM" = "SIMULATOR" ]; then
    if [ "$IOS_ARCH" = "arm64" ]; then
        TARGET_TRIPLE="aarch64-apple-ios-sim"
    else
        TARGET_TRIPLE="x86_64-apple-ios-sim"
    fi
elif [ "$IOS_PLATFORM" = "WATCHOS" ]; then
    TARGET_TRIPLE="arm64_32-apple-watchos"
fi

# Set up build and install directories
CAFFE2_ROOT="$(pwd)"
INSTALL_PREFIX="${REPO_ROOT}/target/${TARGET_TRIPLE}"
BUILD_ROOT="${INSTALL_PREFIX}/build/pytorch"

if [ $CLEAN_BUILD -eq 1 ]; then
    echo -e "${YELLOW}Cleaning build directory...${NC}"
    rm -rf "${BUILD_ROOT}"
fi

mkdir -p "${BUILD_ROOT}"

# Prepare CMake arguments
CMAKE_ARGS=()

# Python configuration
CMAKE_ARGS+=("-DCMAKE_PREFIX_PATH=$($PYTHON -c 'import sysconfig; print(sysconfig.get_path("purelib"))')")
CMAKE_ARGS+=("-DPython_EXECUTABLE=$($PYTHON -c 'import sys; print(sys.executable)')")

# Use Ninja
CMAKE_ARGS+=("-GNinja")
CMAKE_ARGS+=("-DCMAKE_MAKE_PROGRAM=${NINJA_PATH}")

# Suppress CMake deprecation warnings
CMAKE_ARGS+=("-DCMAKE_WARN_DEPRECATED=OFF")

# Determine SDK for compiler detection
if [ "$IOS_PLATFORM" = "OS" ]; then
    IOS_SDK="iphoneos"
elif [ "$IOS_PLATFORM" = "SIMULATOR" ]; then
    IOS_SDK="iphonesimulator"
elif [ "$IOS_PLATFORM" = "WATCHOS" ]; then
    IOS_SDK="watchos"
fi

# Set compilers (required for iOS cross-compilation with Objective-C)
CMAKE_ARGS+=("-DCMAKE_C_COMPILER=$(xcrun --sdk ${IOS_SDK} --find clang)")
CMAKE_ARGS+=("-DCMAKE_CXX_COMPILER=$(xcrun --sdk ${IOS_SDK} --find clang++)")
CMAKE_ARGS+=("-DCMAKE_OBJC_COMPILER=$(xcrun --sdk ${IOS_SDK} --find clang)")
CMAKE_ARGS+=("-DCMAKE_OBJCXX_COMPILER=$(xcrun --sdk ${IOS_SDK} --find clang++)")

# iOS toolchain
CMAKE_ARGS+=("-DCMAKE_TOOLCHAIN_FILE=${CAFFE2_ROOT}/cmake/iOS.cmake")
CMAKE_ARGS+=("-DIOS_PLATFORM=${IOS_PLATFORM}")
CMAKE_ARGS+=("-DIOS_ARCH=${IOS_ARCH}")

# Build configuration
CMAKE_ARGS+=("-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}")
CMAKE_ARGS+=("-DCMAKE_BUILD_TYPE=${BUILD_TYPE}")
CMAKE_ARGS+=("-DBUILD_SHARED_LIBS=OFF")  # iOS always uses static libraries

# Bitcode
if [ $ENABLE_BITCODE -eq 1 ]; then
    CMAKE_ARGS+=("-DCMAKE_C_FLAGS=-fembed-bitcode")
    CMAKE_ARGS+=("-DCMAKE_CXX_FLAGS=-fembed-bitcode -fobjc-arc")
else
    CMAKE_ARGS+=("-DCMAKE_CXX_FLAGS=-fobjc-arc")
fi

# Lite interpreter
if [ $BUILD_LITE_INTERPRETER -eq 1 ]; then
    CMAKE_ARGS+=("-DBUILD_LITE_INTERPRETER=ON")
    CMAKE_ARGS+=("-DUSE_LITE_INTERPRETER_PROFILER=OFF")
else
    CMAKE_ARGS+=("-DBUILD_LITE_INTERPRETER=OFF")
fi

# Features
if [ $USE_PYTORCH_METAL -eq 1 ]; then
    CMAKE_ARGS+=("-DUSE_PYTORCH_METAL=ON")
fi

if [ $USE_COREML_DELEGATE -eq 1 ]; then
    CMAKE_ARGS+=("-DUSE_COREML_DELEGATE=ON")
fi

# Disable Python and tests
CMAKE_ARGS+=("-DBUILD_PYTHON=OFF")
CMAKE_ARGS+=("-DBUILD_TEST=OFF")
CMAKE_ARGS+=("-DBUILD_BINARY=OFF")

# Disable unused dependencies
CMAKE_ARGS+=("-DUSE_CUDA=OFF")
CMAKE_ARGS+=("-DUSE_ITT=OFF")
CMAKE_ARGS+=("-DUSE_GFLAGS=OFF")
CMAKE_ARGS+=("-DUSE_OPENCV=OFF")
CMAKE_ARGS+=("-DUSE_MPI=OFF")
CMAKE_ARGS+=("-DUSE_NUMPY=OFF")
CMAKE_ARGS+=("-DUSE_MKLDNN=OFF")
CMAKE_ARGS+=("-DUSE_KINETO=OFF")
CMAKE_ARGS+=("-DUSE_PROF=OFF")

# Performance: use mimalloc allocator
CMAKE_ARGS+=("-DUSE_MIMALLOC=ON")

# Disable QNNPACK for watchOS
if [ "$IOS_PLATFORM" = "WATCHOS" ]; then
    CMAKE_ARGS+=("-DUSE_PYTORCH_QNNPACK=OFF")
else
    CMAKE_ARGS+=("-DUSE_NNPACK=OFF")
fi

# Threading
CMAKE_ARGS+=("-DCMAKE_THREAD_LIBS_INIT=-lpthread")
CMAKE_ARGS+=("-DCMAKE_HAVE_THREADS_LIBRARY=1")
CMAKE_ARGS+=("-DCMAKE_USE_PTHREADS_INIT=1")

# Protobuf - iOS needs host protoc for cross-compilation
# Check for custom-built Protobuf (should use macOS host protoc)
HOST_PROTOC="${REPO_ROOT}/target/aarch64-apple-darwin/bin/protoc"
if [ ! -f "${HOST_PROTOC}" ]; then
    HOST_PROTOC="${REPO_ROOT}/target/x86_64-apple-darwin/bin/protoc"
fi

CUSTOM_PROTOBUF_LIB="${INSTALL_PREFIX}/lib/libprotobuf.a"
CUSTOM_PROTOBUF_CMAKE_DIR="${INSTALL_PREFIX}/lib/cmake/protobuf"

if [ -f "${HOST_PROTOC}" ] && [ -f "${CUSTOM_PROTOBUF_LIB}" ]; then
    echo -e "${GREEN}Using custom-built static Protobuf with host protoc${NC}"
    CMAKE_ARGS+=("-DBUILD_CUSTOM_PROTOBUF=OFF")
    CMAKE_ARGS+=("-DCAFFE2_CUSTOM_PROTOC_EXECUTABLE=${HOST_PROTOC}")
    CMAKE_ARGS+=("-DProtobuf_PROTOC_EXECUTABLE=${HOST_PROTOC}")
    # Point find_package(Protobuf CONFIG) to our custom protobuf
    CMAKE_ARGS+=("-DProtobuf_DIR=${CUSTOM_PROTOBUF_CMAKE_DIR}")
else
    echo -e "${RED}Error: Custom protobuf not found!${NC}"
    echo "Build host protoc first: ./build-protobuf.sh --target aarch64-apple-darwin (or x86_64-apple-darwin)"
    echo "Then build iOS protobuf: ./build-protobuf.sh --target ${TARGET_TRIPLE}"
    exit 1
fi

# Verbose
if [ $VERBOSE -eq 1 ]; then
    CMAKE_ARGS+=("-DCMAKE_VERBOSE_MAKEFILE=1")
fi

# Display build configuration
echo ""
echo -e "${GREEN}=== iOS Build Configuration ===${NC}"
echo "Target triple:      ${TARGET_TRIPLE}"
echo "Platform:           ${IOS_PLATFORM}"
echo "Architecture:       ${IOS_ARCH}"
echo "Build type:         ${BUILD_TYPE}"
echo "Python:             ${PYTHON}"
echo "Output directory:   ${BUILD_ROOT}"
echo "USE_PYTORCH_METAL:  ${USE_PYTORCH_METAL}"
echo "USE_COREML:         ${USE_COREML_DELEGATE}"
echo "BUILD_LITE:         ${BUILD_LITE_INTERPRETER}"
echo "ENABLE_BITCODE:     ${ENABLE_BITCODE}"
echo -e "${GREEN}===================================${NC}"
echo ""

# Run CMake configuration
echo -e "${YELLOW}Running CMake configuration...${NC}"
cd "${BUILD_ROOT}"
"${CMAKE_PATH}" "${CAFFE2_ROOT}" "${CMAKE_ARGS[@]}"

# Determine number of parallel jobs
NCPU=$(sysctl -n hw.ncpu)

# Build and install
echo -e "${YELLOW}Building with ${NCPU} parallel jobs...${NC}"
"${CMAKE_PATH}" --build . --target install -- "-j${NCPU}"

# Copy all build artifacts to sysroot
echo -e "${YELLOW}Copying libraries and headers to sysroot...${NC}"
cp -rf "${BUILD_ROOT}/lib/"* "${INSTALL_PREFIX}/lib/" 2>/dev/null || true
cp -rf "${BUILD_ROOT}/include/"* "${INSTALL_PREFIX}/include/" 2>/dev/null || true

echo ""
echo -e "${GREEN}iOS build completed successfully!${NC}"
echo ""
echo "Target: ${TARGET_TRIPLE}"
echo ""
echo "Library files:"
echo "  ${BUILD_ROOT}/lib/"
echo ""
echo "Header files:"
echo "  ${BUILD_ROOT}/include/"
echo ""
echo "To use in Xcode:"
echo "  1. Add '${BUILD_ROOT}/include' to Header Search Paths"
echo "  2. Add '${BUILD_ROOT}/lib' to Library Search Paths"
echo "  3. Link against the static libraries"
echo ""
