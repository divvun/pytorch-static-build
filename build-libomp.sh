#!/bin/bash
#
# build-libomp.sh - Build LLVM OpenMP runtime as static library
#
# Usage:
#   ./build-libomp.sh --target aarch64-apple-darwin
#   ./build-libomp.sh --target x86_64-unknown-linux-gnu
#   ./build-libomp.sh --target x86_64-apple-darwin --debug
#

set -e

# Windows: Auto-detect and add MSVC to PATH if needed
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    export PATH=$PATH:/c/msys2/usr/bin

    if ! command -v cl.exe &> /dev/null; then
        # Common MSVC locations
        VS_PATHS=(
            "/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC"
            "/c/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"
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
            echo "Warning: Could not locate MSVC automatically"
            echo "MSVC will be required for Windows builds"
        fi
    fi
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
            echo "  x86_64-pc-windows-msvc      Windows x64 (not recommended - static not officially supported)"
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

echo -e "${GREEN}Building LLVM OpenMP Runtime (libomp)${NC}"

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
        echo -e "${YELLOW}Warning: Static OpenMP is not officially supported on Windows${NC}"
        ;;
    *)
        echo -e "${RED}Error: Unsupported target triple: $TARGET_TRIPLE${NC}"
        exit 1
        ;;
esac

# Check for required tools
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

if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git not found${NC}"
    exit 1
fi

# Set up paths
LLVM_PROJECT_DIR="${REPO_ROOT}/llvm-project"
BUILD_ROOT="${REPO_ROOT}/target/${TARGET_TRIPLE}/build/openmp"
INSTALL_PREFIX="${REPO_ROOT}/target/${TARGET_TRIPLE}"

# Clone LLVM project if not already present
if [ ! -d "${LLVM_PROJECT_DIR}" ]; then
    echo -e "${YELLOW}Cloning LLVM project (shallow clone)...${NC}"
    git clone --depth 1 https://github.com/llvm/llvm-project.git "${LLVM_PROJECT_DIR}"
else
    echo -e "${GREEN}LLVM project already exists at ${LLVM_PROJECT_DIR}${NC}"
fi

# Verify OpenMP runtime directory exists
if [ ! -d "${LLVM_PROJECT_DIR}/openmp/runtime" ]; then
    echo -e "${RED}Error: OpenMP runtime not found at ${LLVM_PROJECT_DIR}/openmp/runtime${NC}"
    echo "Try deleting llvm-project/ and re-running to clone fresh"
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

# Prepare CMake arguments
CMAKE_ARGS=()

# Generator
CMAKE_ARGS+=("-GNinja")
CMAKE_ARGS+=("-DCMAKE_MAKE_PROGRAM=${NINJA_PATH}")

# Build configuration
CMAKE_ARGS+=("-DCMAKE_BUILD_TYPE=${BUILD_TYPE}")
CMAKE_ARGS+=("-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}")

# Set C++17 standard explicitly for consistent Abseil string_view detection
CMAKE_ARGS+=("-DCMAKE_CXX_STANDARD=17")

# Compilers
CMAKE_ARGS+=("-DCMAKE_C_COMPILER=${CC}")
CMAKE_ARGS+=("-DCMAKE_CXX_COMPILER=${CXX}")

# Critical option: Build static library
CMAKE_ARGS+=("-DLIBOMP_ENABLE_SHARED=OFF")

# Position independent code (needed for linking static lib into shared libs)
CMAKE_ARGS+=("-DCMAKE_POSITION_INDEPENDENT_CODE=ON")

# Disable testing and examples
CMAKE_ARGS+=("-DOPENMP_ENABLE_TESTING=OFF")
CMAKE_ARGS+=("-DLIBOMP_OMPT_SUPPORT=OFF")  # Disable OMPT (OpenMP Tools Interface) for simpler build

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
echo -e "${GREEN}=== OpenMP Build Configuration ===${NC}"
echo "Target triple:      ${TARGET_TRIPLE}"
echo "Build type:         ${BUILD_TYPE}"
echo "Platform:           ${PLATFORM}"
echo "C compiler:         ${CC}"
echo "C++ compiler:       ${CXX}"
echo "LLVM source:        ${LLVM_PROJECT_DIR}"
echo "Build directory:    ${BUILD_ROOT}"
echo "Install prefix:     ${INSTALL_PREFIX}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Run CMake configuration
echo -e "${YELLOW}Running CMake configuration...${NC}"
cd "${BUILD_ROOT}"
"${CMAKE_PATH}" "${LLVM_PROJECT_DIR}/openmp" "${CMAKE_ARGS[@]}"

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
"${CMAKE_PATH}" --build . --target install -- "-j${MAX_JOBS}"

echo ""
echo -e "${GREEN}OpenMP build completed successfully!${NC}"
echo ""
echo "Target: ${TARGET_TRIPLE}"
echo ""
echo "Library files:"
ls -lh "${INSTALL_PREFIX}/lib/"libomp* 2>/dev/null || echo "  (none found - check build output)"
echo ""
echo "Header files:"
ls -lh "${INSTALL_PREFIX}/include/"omp* 2>/dev/null || echo "  (none found - check build output)"
echo ""
echo "You can now link against: ${INSTALL_PREFIX}/lib/libomp.a"
echo ""
