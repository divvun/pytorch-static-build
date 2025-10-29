#!/bin/bash
#
# build-icu4c.sh - Build ICU (International Components for Unicode) as static libraries
#
# Usage:
#   ./build-icu4c.sh --target aarch64-apple-darwin
#   ./build-icu4c.sh --target x86_64-unknown-linux-gnu
#   ./build-icu4c.sh --target x86_64-apple-darwin --debug
#

set -e

# Prevent MSYS2 from converting Windows paths in these variables
export MSYS2_ARG_CONV_EXCL="*"
export MSYS2_ENV_CONV_EXCL="LIB;INCLUDE"

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

echo -e "${GREEN}Building ICU (International Components for Unicode)${NC}"

# Detect platform from target triple
case "$TARGET_TRIPLE" in
    *-apple-darwin)
        PLATFORM="darwin"
        ICU_PLATFORM="MacOSX"
        ;;
    *-apple-ios*|*-apple-watchos*)
        PLATFORM="darwin"
        ICU_PLATFORM="MacOSX"
        ;;
    *-linux-*)
        PLATFORM="linux"
        ICU_PLATFORM="Linux"
        ;;
    *-windows-*)
        PLATFORM="windows"
        ICU_PLATFORM="MSYS/MSVC"
        ;;
    *)
        echo -e "${RED}Error: Unsupported target triple: $TARGET_TRIPLE${NC}"
        exit 1
        ;;
esac

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

                        # Add MSVC libraries and includes (convert to Windows paths)
                        MSVC_LIB_PATH=$(cygpath -w "$VS_BASE/$MSVC_VERSION/lib/x64")
                        MSVC_INCLUDE_PATH=$(cygpath -w "$VS_BASE/$MSVC_VERSION/include")
                        export LIB="$MSVC_LIB_PATH"
                        export INCLUDE="$MSVC_INCLUDE_PATH"
                        echo "Added MSVC libraries to LIB"
                        echo "Added MSVC includes to INCLUDE"

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

    # Windows: Add Windows SDK to LIB and INCLUDE
    SDK_BASE="/c/Program Files (x86)/Windows Kits/10"
    if [ -d "$SDK_BASE/Include" ]; then
        # Find latest SDK version
        SDK_VERSION=$(ls -1 "$SDK_BASE/Include" 2>/dev/null | grep -E '^\d+\.' | sort -V | tail -1)
        if [ -n "$SDK_VERSION" ]; then
            # Convert to Windows-style paths using cygpath
            SDK_INCLUDE_UCRT=$(cygpath -w "$SDK_BASE/Include/$SDK_VERSION/ucrt")
            SDK_INCLUDE_UM=$(cygpath -w "$SDK_BASE/Include/$SDK_VERSION/um")
            SDK_INCLUDE_SHARED=$(cygpath -w "$SDK_BASE/Include/$SDK_VERSION/shared")
            SDK_LIB_UCRT=$(cygpath -w "$SDK_BASE/Lib/$SDK_VERSION/ucrt/x64")
            SDK_LIB_UM=$(cygpath -w "$SDK_BASE/Lib/$SDK_VERSION/um/x64")

            export INCLUDE="$SDK_INCLUDE_UCRT;$SDK_INCLUDE_UM;$SDK_INCLUDE_SHARED;$INCLUDE"
            export LIB="$SDK_LIB_UCRT;$SDK_LIB_UM;$LIB"

            echo "Added Windows SDK $SDK_VERSION to environment"
        fi
    fi
fi

# Check for required tools
if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git not found${NC}"
    echo "Install it with your package manager"
    exit 1
fi

if ! command -v make &> /dev/null; then
    if [ "$PLATFORM" = "windows" ]; then
        echo -e "${YELLOW}make not found, installing with pacman...${NC}"
        pacman -S --noconfirm make || {
            echo -e "${RED}Error: Failed to install make${NC}"
            echo "Try manually: pacman -S make"
            exit 1
        }
    else
        echo -e "${RED}Error: make not found${NC}"
        echo "Install it with your package manager"
        exit 1
    fi
fi

# Set up paths
ICU_SOURCE_DIR="${REPO_ROOT}/icu/icu4c/source"
BUILD_ROOT="${REPO_ROOT}/target/${TARGET_TRIPLE}/build/icu"
INSTALL_PREFIX="${REPO_ROOT}/target/${TARGET_TRIPLE}/icu4c"

# Clone ICU (remove existing directory first)
echo -e "${YELLOW}Removing existing ICU directory (if any)...${NC}"
rm -rf "${REPO_ROOT}/icu"
echo -e "${YELLOW}Cloning ICU from GitHub (tag release-77-1)...${NC}"
git clone --depth 1 --branch release-77-1 https://github.com/unicode-org/icu.git "${REPO_ROOT}/icu"

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

    # Set SDK root for proper linking
    export SDKROOT=$(xcrun --show-sdk-path)
elif [ "$PLATFORM" = "linux" ]; then
    # Linux: prefer clang if available, otherwise gcc
    if command -v clang &> /dev/null; then
        export CC=clang
        export CXX=clang++
    else
        export CC=gcc
        export CXX=g++
        ICU_PLATFORM="Linux/gcc"
    fi
else
    # Windows
    export CC=cl.exe
    export CXX=cl.exe
fi

# Set build flags based on build type
case "$BUILD_TYPE" in
    Debug)
        CFLAGS_OPT="-O0 -g"
        CXXFLAGS_OPT="-O0 -g"
        ;;
    Release)
        CFLAGS_OPT="-O3"
        CXXFLAGS_OPT="-O3"
        ;;
    RelWithDebInfo)
        CFLAGS_OPT="-O2 -g"
        CXXFLAGS_OPT="-O2 -g"
        ;;
    MinSizeRel)
        CFLAGS_OPT="-Os"
        CXXFLAGS_OPT="-Os"
        ;;
esac

# Prepare flags
export CFLAGS="${CFLAGS_OPT}"
export CXXFLAGS="${CXXFLAGS_OPT}"

# On Windows, add U_STATIC_IMPLEMENTATION for static library builds
if [ "$PLATFORM" = "windows" ]; then
    export CFLAGS="${CFLAGS} -DU_STATIC_IMPLEMENTATION"
    export CXXFLAGS="${CXXFLAGS} -DU_STATIC_IMPLEMENTATION"
fi

# macOS deployment target
if [ "$PLATFORM" = "darwin" ]; then
    export MACOSX_DEPLOYMENT_TARGET=11.0
fi

# Display build configuration
echo ""
echo -e "${GREEN}=== ICU Build Configuration ===${NC}"
echo "Target triple:      ${TARGET_TRIPLE}"
echo "Build type:         ${BUILD_TYPE}"
echo "Platform:           ${PLATFORM}"
echo "ICU platform:       ${ICU_PLATFORM}"
echo "C compiler:         ${CC}"
echo "C++ compiler:       ${CXX}"
echo "CFLAGS:             ${CFLAGS}"
echo "CXXFLAGS:           ${CXXFLAGS}"
if [ "$PLATFORM" = "darwin" ]; then
    echo "SDKROOT:            ${SDKROOT}"
fi
echo "ICU source:         ${ICU_SOURCE_DIR}"
echo "Build directory:    ${BUILD_ROOT}"
echo "Install prefix:     ${INSTALL_PREFIX}"
echo -e "${GREEN}===================================${NC}"
echo ""

# Run configure
echo -e "${YELLOW}Running ICU configure...${NC}"
cd "${BUILD_ROOT}"

# Build configure arguments
CONFIGURE_ARGS=(
    "--enable-static"
    "--disable-shared"
    "--disable-tests"
    "--disable-samples"
    "--prefix=${INSTALL_PREFIX}"
)

if [ $VERBOSE -eq 1 ]; then
    CONFIGURE_ARGS+=("--enable-debug")
fi

# Use runConfigureICU if available, otherwise use configure directly
if [ -f "${ICU_SOURCE_DIR}/runConfigureICU" ]; then
    echo -e "${YELLOW}Using runConfigureICU for platform: ${ICU_PLATFORM}${NC}"
    "${ICU_SOURCE_DIR}/runConfigureICU" "${ICU_PLATFORM}" "${CONFIGURE_ARGS[@]}"
else
    echo -e "${YELLOW}Using configure directly${NC}"
    "${ICU_SOURCE_DIR}/configure" "${CONFIGURE_ARGS[@]}"
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
make -j${MAX_JOBS}

# Install
echo -e "${YELLOW}Installing to ${INSTALL_PREFIX}...${NC}"
make install

echo ""
echo -e "${GREEN}ICU build completed successfully!${NC}"
echo ""
echo "Target: ${TARGET_TRIPLE}"
echo ""
echo "Library files:"
ls -lh "${INSTALL_PREFIX}/lib/"libicu* 2>/dev/null || echo "  (libraries not found - check build output)"
echo ""
echo "Header files:"
ls -d "${INSTALL_PREFIX}/include/unicode" 2>/dev/null || echo "  (headers not found - check build output)"
echo ""
echo "You can now link against ICU static libraries:"
echo "  libicuuc.a  - Unicode Common"
echo "  libicui18n.a - Internationalization"
echo "  libicudata.a - ICU Data"
echo "  libicuio.a  - ICU I/O (optional)"
echo ""
