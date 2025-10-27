#!/bin/bash
#
# build-protobuf.sh - Build Protocol Buffers as static library from official repository
#
# Usage:
#   ./build-protobuf.sh --target aarch64-apple-darwin
#   ./build-protobuf.sh --target x86_64-unknown-linux-gnu
#   ./build-protobuf.sh --target x86_64-apple-darwin --debug
#

set -e

# Add MSYS2 to PATH if present
if [ -d "/c/msys2/usr/bin" ]; then
    export PATH=/c/msys2/usr/bin:$PATH
fi

# Detect script location and repo root
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="${SCRIPT_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default options
BUILD_TYPE="Release"
CLEAN_BUILD=1
VERBOSE=0
TARGET_TRIPLE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --target)
            TARGET_TRIPLE="$2"
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
        --minsize|--minsizerel)
            BUILD_TYPE="MinSizeRel"
            shift
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --help)
            echo "Usage: $0 --target <triple> [options]"
            echo ""
            echo "Required:"
            echo "  --target <triple>    Target triple (e.g., aarch64-apple-darwin)"
            echo ""
            echo "Build Options:"
            echo "  --no-clean           Skip cleaning build directories (cleans by default)"
            echo "  --debug              Build with debug symbols (-O0 -g)"
            echo "  --release            Build optimized release (default)"
            echo "  --relwithdebinfo     Build optimized with debug symbols (-O2 -g)"
            echo "  --minsize            Build for minimum size"
            echo "  --verbose, -v        Verbose output"
            echo "  --help               Show this help message"
            echo ""
            echo "Supported targets:"
            echo "  aarch64-apple-darwin        macOS Apple Silicon"
            echo "  x86_64-apple-darwin         macOS Intel"
            echo "  aarch64-unknown-linux-gnu   Linux ARM64"
            echo "  x86_64-unknown-linux-gnu    Linux x86_64"
            echo "  x86_64-pc-windows-msvc      Windows x64"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Validate target triple
if [ -z "$TARGET_TRIPLE" ]; then
    echo -e "${RED}Error: --target is required${NC}"
    echo "Run '$0 --help' for usage information"
    exit 1
fi

echo -e "${GREEN}Building Protocol Buffers (libprotobuf)${NC}"

# Detect platform from target triple
case "$TARGET_TRIPLE" in
    *-apple-darwin)
        PLATFORM="darwin"
        ;;
    *-apple-ios*|*-apple-watchos*)
        PLATFORM="darwin"
        ;;
    *-linux-*)
        PLATFORM="linux"
        ;;
    *-windows-*)
        PLATFORM="windows"
        ;;
    *)
        echo -e "${RED}Error: Unsupported target triple: $TARGET_TRIPLE${NC}"
        exit 1
        ;;
esac

# Delegate to PowerShell script on Windows
if [ "$PLATFORM" = "windows" ]; then
    echo -e "${YELLOW}Delegating to PowerShell script for Windows build...${NC}"

    # Build PowerShell arguments from bash arguments
    PS_ARGS="-Target $TARGET_TRIPLE"

    if [ "$BUILD_TYPE" = "Debug" ]; then
        PS_ARGS="$PS_ARGS -Debug"
    elif [ "$BUILD_TYPE" = "RelWithDebInfo" ]; then
        PS_ARGS="$PS_ARGS -RelWithDebInfo"
    elif [ "$BUILD_TYPE" = "MinSizeRel" ]; then
        PS_ARGS="$PS_ARGS -MinSize"
    fi

    if [ $CLEAN_BUILD -eq 0 ]; then
        PS_ARGS="$PS_ARGS -NoClean"
    fi

    # Execute PowerShell script
    pwsh.exe -File "${SCRIPT_DIR}/build-protobuf.ps1" $PS_ARGS
    exit $?
fi

# Windows: Auto-detect and add MSVC to PATH
if [ "$PLATFORM" = "windows" ]; then
    if ! command -v cl.exe &> /dev/null; then
        # Common MSVC locations
        VS_PATHS=(
            "/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC"
            "/c/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"
            "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"
            "/c/Program Files/Microsoft Visual Studio/2022/Professional/VC/Tools/MSVC"
            "/c/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC"
            "/c/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Tools/MSVC"
            "/c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Tools/MSVC"
        )

        MSVC_FOUND=0
        for VS_BASE in "${VS_PATHS[@]}"; do
            if [ -d "$VS_BASE" ]; then
                MSVC_VERSION=$(ls -1 "$VS_BASE" 2>/dev/null | sort -V | tail -1)
                if [ -n "$MSVC_VERSION" ]; then
                    MSVC_BIN="$VS_BASE/$MSVC_VERSION/bin/Hostx64/x64"
                    if [ -f "$MSVC_BIN/cl.exe" ]; then
                        echo "Found MSVC at: $MSVC_BIN"
                        export PATH="$MSVC_BIN:$PATH"
                        export CC=cl.exe
                        export CXX=cl.exe
                        MSVC_FOUND=1
                        break
                    fi
                fi
            fi
        done

        if [ $MSVC_FOUND -eq 0 ]; then
            echo -e "${RED}Error: Could not locate MSVC automatically${NC}"
            echo ""
            echo "Please ensure you have Visual Studio 2022 or 2019 installed with C++ build tools"
            echo "Or manually add MSVC to PATH:"
            echo "  export PATH=\"/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/<version>/bin/Hostx64/x64:\$PATH\""
            echo ""
            echo "Download Visual Studio Build Tools from:"
            echo "  https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022"
            exit 1
        fi
    fi
fi

# Debug: Print PATH to help diagnose issues
echo "PATH: $PATH"

# Check for required tools
if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git not found${NC}"
    echo "Install it with your package manager"
    exit 1
fi

if ! command -v cmake &> /dev/null; then
    if [ "$PLATFORM" = "darwin" ]; then
        echo -e "${RED}Error: cmake not found${NC}"
        echo "Install it with: brew install cmake"
        exit 1
    elif [ "$PLATFORM" = "windows" ]; then
        echo -e "${YELLOW}cmake not found, installing with pacman...${NC}"
        pacman -S --noconfirm cmake || {
            echo -e "${RED}Error: Failed to install cmake${NC}"
            echo "Try manually: pacman -S cmake"
            exit 1
        }
    else
        echo -e "${RED}Error: cmake not found${NC}"
        echo "Install it with your package manager (e.g., apt install cmake)"
        exit 1
    fi
fi

if ! command -v ninja &> /dev/null; then
    if [ "$PLATFORM" = "darwin" ]; then
        echo -e "${RED}Error: ninja not found${NC}"
        echo "Install it with: brew install ninja"
        exit 1
    elif [ "$PLATFORM" = "windows" ]; then
        echo -e "${YELLOW}ninja not found, installing with pacman...${NC}"
        pacman -S --noconfirm ninja || {
            echo -e "${RED}Error: Failed to install ninja${NC}"
            echo "Try manually: pacman -S ninja"
            exit 1
        }
    else
        echo -e "${RED}Error: ninja not found${NC}"
        echo "Install it with your package manager (e.g., apt install ninja-build)"
        exit 1
    fi
fi

# Set up paths
PROTOBUF_SOURCE_DIR="${REPO_ROOT}/protobuf"
BUILD_ROOT="${REPO_ROOT}/target/${TARGET_TRIPLE}/build/protobuf"
INSTALL_PREFIX="${REPO_ROOT}/target/${TARGET_TRIPLE}"

# Clone protobuf if not already present
if [ ! -d "${PROTOBUF_SOURCE_DIR}" ]; then
    echo -e "${YELLOW}Cloning Protocol Buffers from GitHub...${NC}"
    git clone --depth 1 --branch main https://github.com/protocolbuffers/protobuf.git "${PROTOBUF_SOURCE_DIR}"
else
    echo -e "${GREEN}Using existing Protocol Buffers source at ${PROTOBUF_SOURCE_DIR}${NC}"
fi

# Verify protobuf CMakeLists.txt exists
if [ ! -f "${PROTOBUF_SOURCE_DIR}/CMakeLists.txt" ]; then
    echo -e "${RED}Error: Protobuf CMakeLists.txt not found at ${PROTOBUF_SOURCE_DIR}/CMakeLists.txt${NC}"
    echo "The protobuf clone might be incomplete or corrupted. Try removing ${PROTOBUF_SOURCE_DIR} and running again."
    exit 1
fi

# Clean build directory if requested
if [ $CLEAN_BUILD -eq 1 ]; then
    echo -e "${YELLOW}Cleaning build directory...${NC}"
    rm -rf "${BUILD_ROOT}"
fi

mkdir -p "${BUILD_ROOT}"

# Set compilers based on platform
if [ "$PLATFORM" = "darwin" ]; then
    # macOS: use clang from Xcode
    export CC=$(xcrun -f clang)
    export CXX=$(xcrun -f clang++)

    # Check for cmake and ninja from homebrew
    ARCH=$(uname -m)
    if [ "${ARCH}" = "arm64" ]; then
        BREW_PREFIX="/opt/homebrew"
    else
        BREW_PREFIX="/usr/local"
    fi
    CMAKE_PATH="${BREW_PREFIX}/bin/cmake"
    NINJA_PATH="${BREW_PREFIX}/bin/ninja"
elif [ "$PLATFORM" = "linux" ]; then
    # Linux: prefer clang if available, otherwise gcc
    if command -v clang &> /dev/null; then
        export CC=clang
        export CXX=clang++
    else
        export CC=gcc
        export CXX=g++
    fi
    CMAKE_PATH=$(which cmake)
    NINJA_PATH=$(which ninja)
else
    # Windows
    CMAKE_PATH=$(which cmake)
    NINJA_PATH=$(which ninja)
fi

# Convert paths to Windows format if on Windows (for PowerShell/CMake)
if [ "$PLATFORM" = "windows" ]; then
    PROTOBUF_SOURCE_DIR=$(cygpath -w "${PROTOBUF_SOURCE_DIR}")
    BUILD_ROOT=$(cygpath -w "${BUILD_ROOT}")
    INSTALL_PREFIX=$(cygpath -w "${INSTALL_PREFIX}")
    NINJA_PATH=$(cygpath -w "${NINJA_PATH}")
    CMAKE_PATH=$(cygpath -w "${CMAKE_PATH}")

    # Prevent path mangling when building CMAKE_ARGS
    export MSYS_NO_PATHCONV=1
    export MSYS2_ARG_CONV_EXCL="*"
fi

# Prepare CMake arguments
CMAKE_ARGS=()

# Generator
CMAKE_ARGS+=("-GNinja")
CMAKE_ARGS+=("-DCMAKE_MAKE_PROGRAM=${NINJA_PATH}")

# Build configuration
CMAKE_ARGS+=("-DCMAKE_BUILD_TYPE=${BUILD_TYPE}")
CMAKE_ARGS+=("-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}")

# Compilers
CMAKE_ARGS+=("-DCMAKE_C_COMPILER=${CC}")
CMAKE_ARGS+=("-DCMAKE_CXX_COMPILER=${CXX}")

# Set C++17 standard explicitly
CMAKE_ARGS+=("-DCMAKE_CXX_STANDARD=17")

# Critical options: Build static libraries
CMAKE_ARGS+=("-Dprotobuf_BUILD_SHARED_LIBS=OFF")

# Force protobuf to fetch and build Abseil instead of using system version
CMAKE_ARGS+=("-Dprotobuf_FORCE_FETCH_DEPENDENCIES=ON")

# Pass Abseil options to avoid inline namespace mangling issues
CMAKE_ARGS+=("-DABSL_ENABLE_INSTALL=ON")
CMAKE_ARGS+=("-DABSL_PROPAGATE_CXX_STD=ON")

# Position independent code (needed for linking static lib into shared libs)
CMAKE_ARGS+=("-DCMAKE_POSITION_INDEPENDENT_CODE=ON")

# Disable testing and examples
CMAKE_ARGS+=("-Dprotobuf_BUILD_TESTS=OFF")
CMAKE_ARGS+=("-Dprotobuf_BUILD_EXAMPLES=OFF")

# Build protoc compiler (needed during PyTorch build)
CMAKE_ARGS+=("-Dprotobuf_BUILD_PROTOC_BINARIES=ON")

# Platform-specific settings
if [ "$PLATFORM" = "darwin" ]; then
    CMAKE_ARGS+=("-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0")
elif [ "$PLATFORM" = "windows" ]; then
    CMAKE_ARGS+=("-DCMAKE_C_COMPILER=cl.exe")
    CMAKE_ARGS+=("-DCMAKE_CXX_COMPILER=cl.exe")
fi

# Verbose
if [ $VERBOSE -eq 1 ]; then
    CMAKE_ARGS+=("-DCMAKE_VERBOSE_MAKEFILE=ON")
fi

# Display build configuration
echo ""
echo -e "${GREEN}=== Protobuf Build Configuration ===${NC}"
echo "Target triple:      ${TARGET_TRIPLE}"
echo "Build type:         ${BUILD_TYPE}"
echo "Platform:           ${PLATFORM}"
echo "C compiler:         ${CC}"
echo "C++ compiler:       ${CXX}"
echo "Protobuf source:    ${PROTOBUF_SOURCE_DIR}"
echo "Build directory:    ${BUILD_ROOT}"
echo "Install prefix:     ${INSTALL_PREFIX}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Run CMake configuration
echo -e "${YELLOW}Running CMake configuration...${NC}"
if [ "$PLATFORM" = "windows" ]; then
    # Use PowerShell for Windows to handle paths with backslashes
    pwsh.exe -Command "Set-Location '${BUILD_ROOT}'; & cmake '${PROTOBUF_SOURCE_DIR}' ${CMAKE_ARGS[*]}"
else
    cd "${BUILD_ROOT}"
    "${CMAKE_PATH}" "${PROTOBUF_SOURCE_DIR}" "${CMAKE_ARGS[@]}"
fi

# Determine number of parallel jobs
if [ -z "$MAX_JOBS" ]; then
    if [ "$PLATFORM" = "darwin" ]; then
        MAX_JOBS=$(sysctl -n hw.ncpu)
    else
        MAX_JOBS=$(nproc 2>/dev/null || echo 4)
    fi
fi

# Build
echo -e "${YELLOW}Building with ${MAX_JOBS} parallel jobs...${NC}"
if [ "$PLATFORM" = "windows" ]; then
    # Use PowerShell for Windows to handle paths with backslashes
    pwsh.exe -Command "Set-Location '${BUILD_ROOT}'; & cmake --build . --target install -- '-j${MAX_JOBS}'"
    # Unset path conversion guards
    unset MSYS_NO_PATHCONV
    unset MSYS2_ARG_CONV_EXCL
else
    cd "${BUILD_ROOT}"
    "${CMAKE_PATH}" --build . --target install -- "-j${MAX_JOBS}"
fi

# Copy Abseil libraries to sysroot (protobuf depends on Abseil)
echo -e "${YELLOW}Copying Abseil libraries to sysroot...${NC}"
ABSEIL_LIBS=$(find "${BUILD_ROOT}" -name "libabsl_*.a" 2>/dev/null || true)
if [ -n "$ABSEIL_LIBS" ]; then
    echo "$ABSEIL_LIBS" | while read -r lib; do
        cp -v "$lib" "${INSTALL_PREFIX}/lib/"
    done
    echo -e "${GREEN}Copied $(echo "$ABSEIL_LIBS" | wc -l | tr -d ' ') Abseil libraries${NC}"
else
    echo -e "${YELLOW}Warning: No Abseil libraries found in build directory${NC}"
fi

# Copy Abseil headers if present
if [ -d "${BUILD_ROOT}/abseil-cpp" ]; then
    echo -e "${YELLOW}Copying Abseil headers...${NC}"
    cp -rf "${BUILD_ROOT}/abseil-cpp/absl" "${INSTALL_PREFIX}/include/" 2>/dev/null || true
elif [ -d "${BUILD_ROOT}/_deps/abseil-cpp-src/absl" ]; then
    echo -e "${YELLOW}Copying Abseil headers...${NC}"
    cp -rf "${BUILD_ROOT}/_deps/abseil-cpp-src/absl" "${INSTALL_PREFIX}/include/" 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}Protobuf build completed successfully!${NC}"
echo ""
echo "Target: ${TARGET_TRIPLE}"
echo ""
echo "Binaries:"
ls -lh "${INSTALL_PREFIX}/bin/"protoc* 2>/dev/null || echo "  (protoc not found - check build output)"
echo ""
echo "Library files:"
ls -lh "${INSTALL_PREFIX}/lib/"libproto* 2>/dev/null || echo "  (libraries not found - check build output)"
echo ""
echo "Abseil libraries:"
if ls "${INSTALL_PREFIX}/lib/"libabsl_*.a 1> /dev/null 2>&1; then
    ls -lh "${INSTALL_PREFIX}/lib/"libabsl_*.a
else
    echo "  (no Abseil libraries found)"
fi
echo ""
echo "Header files:"
ls -d "${INSTALL_PREFIX}/include/google/protobuf" 2>/dev/null || echo "  (headers not found - check build output)"
ls -d "${INSTALL_PREFIX}/include/absl" 2>/dev/null || echo "  (Abseil headers not found - check build output)"
echo ""
echo "You can now use:"
echo "  protoc: ${INSTALL_PREFIX}/bin/protoc"
echo "  libprotobuf.a: ${INSTALL_PREFIX}/lib/libprotobuf.a"
echo "  libabsl_*.a: ${INSTALL_PREFIX}/lib/libabsl_*.a"
echo ""
