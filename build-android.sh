#!/bin/bash
#
# build-android.sh - Build PyTorch for Android using uv for Python environment management
#
# Usage:
#   ./build-android.sh                 # Build for arm64-v8a (default)
#   ./build-android.sh --abi armeabi-v7a  # Build for ARMv7
#   ./build-android.sh --abi x86_64       # Build for x86_64 emulator
#   ./build-android.sh --api 24           # Set minimum API level
#   ./build-android.sh --vulkan           # Enable Vulkan support
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
ANDROID_ABI="arm64-v8a"  # arm64-v8a, armeabi-v7a, x86, x86_64
ANDROID_NATIVE_API_LEVEL="21"  # Minimum Android API level
BUILD_TYPE="Release"  # Release, Debug, MinSizeRel, RelWithDebInfo
CLEAN_BUILD=1
BUILD_LITE_INTERPRETER=0
USE_VULKAN=0
USE_VULKAN_FP16_INFERENCE=0
ANDROID_STL_SHARED=0  # Use static STL by default
VERBOSE=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --abi)
            ANDROID_ABI="$2"
            shift 2
            ;;
        --arm64|--arm64-v8a)
            ANDROID_ABI="arm64-v8a"
            shift
            ;;
        --armv7|--armeabi-v7a)
            ANDROID_ABI="armeabi-v7a"
            shift
            ;;
        --x86)
            ANDROID_ABI="x86"
            shift
            ;;
        --x86_64|--x86-64)
            ANDROID_ABI="x86_64"
            shift
            ;;
        --api)
            ANDROID_NATIVE_API_LEVEL="$2"
            shift 2
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
        --minsize)
            BUILD_TYPE="MinSizeRel"
            shift
            ;;
        --vulkan)
            USE_VULKAN=1
            shift
            ;;
        --vulkan-fp16)
            USE_VULKAN=1
            USE_VULKAN_FP16_INFERENCE=1
            shift
            ;;
        --stl-shared)
            ANDROID_STL_SHARED=1
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
            echo "ABI Options:"
            echo "  --abi <abi>          Android ABI (arm64-v8a, armeabi-v7a, x86, x86_64)"
            echo "  --arm64              Build for arm64-v8a (default)"
            echo "  --armv7              Build for armeabi-v7a"
            echo "  --x86                Build for x86 emulator"
            echo "  --x86_64             Build for x86_64 emulator"
            echo ""
            echo "Build Options:"
            echo "  --api <level>        Android API level (default: 21)"
            echo "  --no-clean           Skip cleaning build directory (cleans by default)"
            echo "  --debug              Build with debug symbols"
            echo "  --release            Build optimized release (default)"
            echo "  --relwithdebinfo     Build optimized with debug symbols"
            echo "  --minsize            Build for minimum size"
            echo ""
            echo "Feature Options:"
            echo "  --vulkan             Enable Vulkan support"
            echo "  --vulkan-fp16        Enable Vulkan with FP16 inference"
            echo "  --stl-shared         Use shared C++ STL (static by default)"
            echo "  --lite               Build Lite Interpreter"
            echo "  --full               Build full interpreter (default)"
            echo "  --verbose, -v        Verbose output"
            echo "  --help               Show this help message"
            echo ""
            echo "Requirements:"
            echo "  ANDROID_NDK environment variable must be set"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Check for ANDROID_NDK
if [ -z "$ANDROID_NDK" ]; then
    echo -e "${RED}Error: ANDROID_NDK environment variable not set${NC}"
    echo ""
    echo "Please set ANDROID_NDK to your Android NDK directory:"
    echo "  export ANDROID_NDK=/path/to/android-ndk"
    echo ""
    echo "Download NDK from: https://developer.android.com/ndk/downloads"
    exit 1
fi

if [ ! -d "$ANDROID_NDK" ]; then
    echo -e "${RED}Error: ANDROID_NDK directory does not exist: $ANDROID_NDK${NC}"
    exit 1
fi

# Get NDK version
ANDROID_NDK_PROPERTIES="$ANDROID_NDK/source.properties"
if [ -f "$ANDROID_NDK_PROPERTIES" ]; then
    ANDROID_NDK_VERSION=$(sed -n 's/^Pkg.Revision[^=]*= *\([0-9]*\)\..*$/\1/p' "$ANDROID_NDK_PROPERTIES")
else
    ANDROID_NDK_VERSION="unknown"
fi

# Check for uv
if ! command -v uv &> /dev/null; then
    echo -e "${RED}Error: uv is not installed${NC}"
    echo "Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

echo -e "${GREEN}Building PyTorch for Android${NC}"

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

# Check for ninja and cmake (use homebrew versions on macOS)
if [ "$(uname)" = "Darwin" ]; then
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
else
    # On Linux, use system cmake/ninja
    if ! command -v ninja &> /dev/null; then
        echo -e "${RED}Error: ninja not found${NC}"
        echo "Install it with your package manager"
        exit 1
    fi

    if ! command -v cmake &> /dev/null; then
        echo -e "${RED}Error: cmake not found${NC}"
        echo "Install it with your package manager"
        exit 1
    fi

    NINJA_PATH=$(which ninja)
    CMAKE_PATH=$(which cmake)
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
case "${ANDROID_ABI}" in
    arm64-v8a)
        TARGET_TRIPLE="aarch64-linux-android"
        ;;
    armeabi-v7a)
        TARGET_TRIPLE="armv7-linux-androideabi"
        ;;
    x86)
        TARGET_TRIPLE="i686-linux-android"
        ;;
    x86_64)
        TARGET_TRIPLE="x86_64-linux-android"
        ;;
    *)
        echo -e "${RED}Error: Unknown Android ABI: ${ANDROID_ABI}${NC}"
        exit 1
        ;;
esac

# Set up build and install directories
CAFFE2_ROOT="$(pwd)"
INSTALL_PREFIX="${REPO_ROOT}/target/${TARGET_TRIPLE}"
BUILD_ROOT="${INSTALL_PREFIX}/build/pytorch"

if [ $CLEAN_BUILD -eq 1 ]; then
    echo -e "${YELLOW}Cleaning build directory...${NC}"
    rm -rf "${BUILD_ROOT}"
fi

mkdir -p "${BUILD_ROOT}"

# Patch pocketfft for Android (no aligned_alloc)
if [ -f third_party/pocketfft/pocketfft_hdronly.h ]; then
    sed -i.bak -e "s/__cplusplus >= 201703L/0/" third_party/pocketfft/pocketfft_hdronly.h
fi

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

# Android toolchain
CMAKE_ARGS+=("-DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK}/build/cmake/android.toolchain.cmake")
CMAKE_ARGS+=("-DANDROID_NDK=${ANDROID_NDK}")
CMAKE_ARGS+=("-DANDROID_ABI=${ANDROID_ABI}")
CMAKE_ARGS+=("-DANDROID_NATIVE_API_LEVEL=${ANDROID_NATIVE_API_LEVEL}")
CMAKE_ARGS+=("-DANDROID_CPP_FEATURES=rtti exceptions")

# Toolchain selection based on NDK version
if (( "${ANDROID_NDK_VERSION:-0}" < 18 )); then
    CMAKE_ARGS+=("-DANDROID_TOOLCHAIN=gcc")
else
    CMAKE_ARGS+=("-DANDROID_TOOLCHAIN=clang")
fi

# STL configuration
if [ $ANDROID_STL_SHARED -eq 1 ]; then
    CMAKE_ARGS+=("-DANDROID_STL=c++_shared")
else
    CMAKE_ARGS+=("-DANDROID_STL=c++_static")
fi

# Build configuration
CMAKE_ARGS+=("-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}")
CMAKE_ARGS+=("-DCMAKE_BUILD_TYPE=${BUILD_TYPE}")
CMAKE_ARGS+=("-DBUILD_SHARED_LIBS=OFF")  # Android always uses static libraries

# Lite interpreter
if [ $BUILD_LITE_INTERPRETER -eq 1 ]; then
    CMAKE_ARGS+=("-DBUILD_LITE_INTERPRETER=ON")
    CMAKE_ARGS+=("-DUSE_LITE_INTERPRETER_PROFILER=OFF")
else
    CMAKE_ARGS+=("-DBUILD_LITE_INTERPRETER=OFF")
fi

# Vulkan support
if [ $USE_VULKAN -eq 1 ]; then
    CMAKE_ARGS+=("-DUSE_VULKAN=ON")
    if [ $USE_VULKAN_FP16_INFERENCE -eq 1 ]; then
        CMAKE_ARGS+=("-DUSE_VULKAN_FP16_INFERENCE=ON")
    fi
else
    CMAKE_ARGS+=("-DUSE_VULKAN=OFF")
fi

# Disable Python and tests
CMAKE_ARGS+=("-DBUILD_PYTHON=OFF")
CMAKE_ARGS+=("-DBUILD_TEST=OFF")
CMAKE_ARGS+=("-DBUILD_BINARY=OFF")
CMAKE_ARGS+=("-DBUILD_MOBILE_BENCHMARK=OFF")
CMAKE_ARGS+=("-DBUILD_MOBILE_TEST=OFF")

# Disable unused dependencies
CMAKE_ARGS+=("-DUSE_CUDA=OFF")
CMAKE_ARGS+=("-DUSE_ITT=OFF")
CMAKE_ARGS+=("-DUSE_GFLAGS=OFF")
CMAKE_ARGS+=("-DUSE_OPENCV=OFF")
CMAKE_ARGS+=("-DUSE_MPI=OFF")
CMAKE_ARGS+=("-DUSE_OPENMP=OFF")
CMAKE_ARGS+=("-DUSE_KINETO=OFF")
CMAKE_ARGS+=("-DUSE_MKLDNN=OFF")
CMAKE_ARGS+=("-DUSE_PROF=OFF")

# Protobuf - Android needs host protoc for cross-compilation
# Check for custom-built Protobuf (should use Linux host protoc)
HOST_PROTOC="${REPO_ROOT}/target/x86_64-unknown-linux-gnu/bin/protoc"
if [ ! -f "${HOST_PROTOC}" ]; then
    HOST_PROTOC="${REPO_ROOT}/target/aarch64-unknown-linux-gnu/bin/protoc"
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
    echo "Build host protoc first: ./build-protobuf.sh --target x86_64-unknown-linux-gnu (or aarch64-unknown-linux-gnu)"
    echo "Then build Android protobuf: ./build-protobuf.sh --target ${TARGET_TRIPLE}"
    exit 1
fi

# Performance: use mimalloc allocator
CMAKE_ARGS+=("-DUSE_MIMALLOC=ON")

# Verbose
if [ $VERBOSE -eq 1 ]; then
    CMAKE_ARGS+=("-DCMAKE_VERBOSE_MAKEFILE=1")
fi

# Display build configuration
echo ""
echo -e "${GREEN}=== Android Build Configuration ===${NC}"
echo "Target triple:      ${TARGET_TRIPLE}"
echo "Android NDK:        ${ANDROID_NDK}"
echo "NDK version:        ${ANDROID_NDK_VERSION}"
echo "ABI:                ${ANDROID_ABI}"
echo "API level:          ${ANDROID_NATIVE_API_LEVEL}"
echo "Build type:         ${BUILD_TYPE}"
echo "Python:             ${PYTHON}"
echo "Output directory:   ${BUILD_ROOT}"
echo "BUILD_LITE:         ${BUILD_LITE_INTERPRETER}"
echo "USE_VULKAN:         ${USE_VULKAN}"
echo "STL:                $([ $ANDROID_STL_SHARED -eq 1 ] && echo 'shared' || echo 'static')"
echo -e "${GREEN}====================================${NC}"
echo ""

# Run CMake configuration
echo -e "${YELLOW}Running CMake configuration...${NC}"
cd "${BUILD_ROOT}"
"${CMAKE_PATH}" "${CAFFE2_ROOT}" "${CMAKE_ARGS[@]}"

# Determine number of parallel jobs
if [ -z "$MAX_JOBS" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        MAX_JOBS=$(sysctl -n hw.ncpu)
    else
        MAX_JOBS=$(nproc)
    fi
fi

# Build
echo -e "${YELLOW}Building with ${MAX_JOBS} parallel jobs...${NC}"
"${CMAKE_PATH}" --build . --target install -- "-j${MAX_JOBS}"

# Copy all build artifacts to sysroot
echo -e "${YELLOW}Copying libraries and headers to sysroot...${NC}"
cp -rf "${BUILD_ROOT}/lib/"* "${INSTALL_PREFIX}/lib/" 2>/dev/null || true
cp -rf "${BUILD_ROOT}/include/"* "${INSTALL_PREFIX}/include/" 2>/dev/null || true

echo ""
echo -e "${GREEN}Android build completed successfully!${NC}"
echo ""
echo "Target: ${TARGET_TRIPLE}"
echo ""
echo "Library files:"
echo "  ${BUILD_ROOT}/lib/"
echo ""
echo "Header files:"
echo "  ${BUILD_ROOT}/include/"
echo ""
echo "To use in Android Studio:"
echo "  1. Copy '${BUILD_ROOT}/include' to your project's jni/include"
echo "  2. Copy '${BUILD_ROOT}/lib' to your project's jniLibs/${ANDROID_ABI}"
echo "  3. Link against the static libraries in your CMakeLists.txt"
echo ""
echo "To build for multiple ABIs:"
echo "  ./build-android.sh --abi arm64-v8a"
echo "  ./build-android.sh --abi armeabi-v7a"
echo "  ./build-android.sh --abi x86_64"
echo ""
