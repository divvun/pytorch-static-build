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
    *-linux-*)
        PLATFORM="linux"
        ICU_PLATFORM="Linux"
        ;;
    *-windows-*)
        PLATFORM="windows"
        ICU_PLATFORM="Cygwin/MSVC"
        ;;
    *)
        echo -e "${RED}Error: Unsupported target triple: $TARGET_TRIPLE${NC}"
        exit 1
        ;;
esac

# Check for required tools
if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git not found${NC}"
    echo "Install it with your package manager"
    exit 1
fi

if ! command -v make &> /dev/null; then
    if [ "$PLATFORM" = "windows" ]; then
        echo -e "${YELLOW}make not found, installing with pacman...${NC}"
        pacman -S --noconfirm mingw-w64-x86_64-make || {
            echo -e "${RED}Error: Failed to install make${NC}"
            echo "Try manually: pacman -S mingw-w64-x86_64-make"
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
INSTALL_PREFIX="${REPO_ROOT}/target/${TARGET_TRIPLE}"

# Clone ICU if not already present
if [ ! -d "${REPO_ROOT}/icu" ]; then
    echo -e "${YELLOW}Cloning ICU from GitHub...${NC}"
    git clone --depth 1 https://github.com/unicode-org/icu.git "${REPO_ROOT}/icu"
else
    echo -e "${GREEN}Using existing ICU source at ${REPO_ROOT}/icu${NC}"
fi

# Verify ICU source directory exists
if [ ! -f "${ICU_SOURCE_DIR}/configure" ]; then
    echo -e "${RED}Error: ICU configure script not found at ${ICU_SOURCE_DIR}/configure${NC}"
    echo "The ICU clone might be incomplete or corrupted. Try removing ${REPO_ROOT}/icu and running again."
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
