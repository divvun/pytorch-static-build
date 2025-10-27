#!/bin/bash
#
# build.sh - Unified build script for PyTorch C++ libraries
#
# Usage:
#   ./build.sh --target <triple>           # Build for specified target
#   ./build.sh --target aarch64-apple-darwin --debug
#   ./build.sh --help                      # Show available targets
#

set -e

# Add MSYS2 to PATH if present
if [ -d "/c/msys2/usr/bin" ]; then
    export PATH=/c/msys2/usr/bin:$PATH
fi

# Detect script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Show usage
show_help() {
    echo "Usage: $0 --target <triple> [options]"
    echo ""
    echo "Target Triples:"
    echo ""
    echo "  macOS:"
    echo "    aarch64-apple-darwin       macOS on Apple Silicon"
    echo "    x86_64-apple-darwin        macOS on Intel"
    echo ""
    echo "  iOS:"
    echo "    aarch64-apple-ios          iOS device (iPhone/iPad)"
    echo "    aarch64-apple-ios-sim      iOS simulator on Apple Silicon"
    echo "    x86_64-apple-ios-sim       iOS simulator on Intel"
    echo "    arm64_32-apple-watchos     watchOS (Apple Watch)"
    echo ""
    echo "  Android:"
    echo "    aarch64-linux-android      Android arm64-v8a"
    echo "    armv7-linux-androideabi    Android armeabi-v7a"
    echo "    x86_64-linux-android       Android x86_64"
    echo "    i686-linux-android         Android x86"
    echo ""
    echo "  Linux:"
    echo "    x86_64-unknown-linux-gnu   Linux x86_64"
    echo "    aarch64-unknown-linux-gnu  Linux ARM64"
    echo ""
    echo "  Windows:"
    echo "    x86_64-pc-windows-msvc     Windows x64 (MSVC)"
    echo "    i686-pc-windows-msvc       Windows x86 (MSVC)"
    echo ""
    echo "Dependency Options:"
    echo "  --no-deps                  Skip building dependencies (default: build deps)"
    echo ""
    echo "Build Options (passed to underlying script):"
    echo "  --debug                    Build with debug symbols"
    echo "  --release                  Build optimized release (default)"
    echo "  --relwithdebinfo           Build optimized with debug symbols"
    echo "  --minsize                  Build for minimum size"
    echo "  --no-clean                 Skip cleaning build directory"
    echo "  --verbose, -v              Verbose output"
    echo ""
    echo "Platform-specific options:"
    echo "  iOS: --metal, --no-metal, --coreml, --bitcode"
    echo "  Android: --vulkan, --vulkan-fp16, --api <level>"
    echo "  macOS/Linux: --distributed, --no-distributed"
    echo "  Windows: --arch (x64, x86)"
    echo ""
    echo "Examples:"
    echo "  ./build.sh --target aarch64-apple-darwin"
    echo "  ./build.sh --target aarch64-apple-ios --debug"
    echo "  ./build.sh --target aarch64-linux-android --vulkan"
    echo "  ./build.sh --target x86_64-unknown-linux-gnu --distributed"
    echo "  ./build.sh --target x86_64-pc-windows-msvc --no-deps"
}

# Parse target flag and options
TARGET=""
WITH_DEPS=1  # Build dependencies by default
COMMON_ARGS=()  # Args passed to both dependency builds and PyTorch build
PLATFORM_ARGS=()  # Args passed only to PyTorch build

while [[ $# -gt 0 ]]; do
    case $1 in
        --target)
            TARGET="$2"
            shift 2
            ;;
        --no-deps)
            WITH_DEPS=0
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        # Common args that apply to all builds
        --debug|--release|--relwithdebinfo|--minsize|--minsizerel|--no-clean|--verbose|-v)
            COMMON_ARGS+=("$1")
            shift
            ;;
        # Platform-specific args (for PyTorch only)
        *)
            PLATFORM_ARGS+=("$1")
            shift
            ;;
    esac
done

# Combine args for PyTorch build
BUILD_ARGS=("${COMMON_ARGS[@]}" "${PLATFORM_ARGS[@]}")

# Check if target was specified
if [ -z "$TARGET" ]; then
    echo -e "${RED}Error: --target flag is required${NC}"
    echo ""
    show_help
    exit 1
fi

case "$TARGET" in
    *-windows-*)
        export PATH=$PATH:/c/msys2/usr/bin
        ;;
esac

# Clean target directory if requested
CLEAN_BUILD=1
for arg in "${COMMON_ARGS[@]}"; do
    if [[ "$arg" == "--no-clean" ]]; then
        CLEAN_BUILD=0
        break
    fi
done

if [ $CLEAN_BUILD -eq 1 ]; then
    TARGET_DIR="${SCRIPT_DIR}/target/${TARGET}"
    if [ -d "${TARGET_DIR}" ]; then
        echo -e "${YELLOW}Cleaning target directory: ${TARGET_DIR}${NC}"
        rm -rf "${TARGET_DIR}"
    fi
fi

# Build dependencies if requested
if [ $WITH_DEPS -eq 1 ]; then
    echo "--- :package: Building dependencies for ${TARGET}"
    echo ""

    INSTALL_PREFIX="${SCRIPT_DIR}/target/${TARGET}"
    echo -e "${YELLOW}Install prefix: ${INSTALL_PREFIX}${NC}"
    echo ""

    # 1. Build Protobuf
    # Always build host protoc for cross-compilation to ensure correct version
    HOST_ARCH=$(uname -m)
    if [ "$HOST_ARCH" = "arm64" ]; then
        HOST_DARWIN_TARGET="aarch64-apple-darwin"
    else
        HOST_DARWIN_TARGET="x86_64-apple-darwin"
    fi

    # Determine host Linux target for potential cross-compilation
    if [ "$HOST_ARCH" = "aarch64" ]; then
        HOST_LINUX_TARGET="aarch64-unknown-linux-gnu"
    else
        HOST_LINUX_TARGET="x86_64-unknown-linux-gnu"
    fi

    case "$TARGET" in
        aarch64-apple-darwin|x86_64-apple-darwin)
            # macOS: Check if cross-compiling
            if [ "$TARGET" != "$HOST_DARWIN_TARGET" ]; then
                echo "--- :hammer_and_wrench: Building host protoc for ${HOST_DARWIN_TARGET}"
                "${SCRIPT_DIR}/build-protobuf.sh" --target "${HOST_DARWIN_TARGET}" "${COMMON_ARGS[@]}"
            fi
            ;;
        aarch64-apple-ios|aarch64-apple-ios-sim|x86_64-apple-ios-sim|arm64_32-apple-watchos)
            # iOS/watchOS: Need macOS host protoc
            echo "--- :hammer_and_wrench: Building host protoc for ${HOST_DARWIN_TARGET}"
            "${SCRIPT_DIR}/build-protobuf.sh" --target "${HOST_DARWIN_TARGET}" "${COMMON_ARGS[@]}"
            ;;
        x86_64-unknown-linux-gnu|aarch64-unknown-linux-gnu)
            # Linux: Check if cross-compiling
            if [ "$TARGET" != "$HOST_LINUX_TARGET" ]; then
                echo "--- :hammer_and_wrench: Building host protoc for ${HOST_LINUX_TARGET}"
                "${SCRIPT_DIR}/build-protobuf.sh" --target "${HOST_LINUX_TARGET}" "${COMMON_ARGS[@]}"
            fi
            ;;
        *-linux-android)
            # Android: Need Linux host protoc
            echo "--- :hammer_and_wrench: Building host protoc for ${HOST_LINUX_TARGET}"
            "${SCRIPT_DIR}/build-protobuf.sh" --target "${HOST_LINUX_TARGET}" "${COMMON_ARGS[@]}"
            ;;
    esac

    # Build target protobuf - always build to ensure correct version
    echo "--- :package: Building Protobuf for ${TARGET}"
    "${SCRIPT_DIR}/build-protobuf.sh" --target "${TARGET}" "${COMMON_ARGS[@]}"

    # 2. Build OpenMP (only for macOS, Linux, Windows)
    case "$TARGET" in
        *-apple-darwin|*-unknown-linux-gnu|*-pc-windows-msvc)
            echo "--- :fire: Building OpenMP for ${TARGET}"
            "${SCRIPT_DIR}/build-libomp.sh" --target "${TARGET}" "${COMMON_ARGS[@]}"
            ;;
        *)
            echo -e "${GREEN}Skipping OpenMP for ${TARGET} (not needed for this platform)${NC}"
            ;;
    esac

    # 3. Build ICU4C (all platforms)
    echo "--- :globe_with_meridians: Building ICU4C for ${TARGET}"
    "${SCRIPT_DIR}/build-icu4c.sh" --target "${TARGET}" "${COMMON_ARGS[@]}"

    echo ""
    echo -e "${GREEN}Dependencies built successfully${NC}"
    echo ""
fi

# Determine which build script to use and what flags to pass
case "$TARGET" in
    # macOS targets
    aarch64-apple-darwin)
        echo "--- :apple: Building PyTorch for macOS (Apple Silicon)"
        exec "${SCRIPT_DIR}/build-macos.sh" --target "${TARGET}" "${BUILD_ARGS[@]}"
        ;;
    x86_64-apple-darwin)
        echo "--- :apple: Building PyTorch for macOS (Intel)"
        exec "${SCRIPT_DIR}/build-macos.sh" --target "${TARGET}" "${BUILD_ARGS[@]}"
        ;;

    # iOS targets
    aarch64-apple-ios)
        echo "--- :iphone: Building PyTorch for iOS device"
        exec "${SCRIPT_DIR}/build-ios.sh" --device "${BUILD_ARGS[@]}"
        ;;
    aarch64-apple-ios-sim)
        echo "--- :iphone: Building PyTorch for iOS simulator (Apple Silicon)"
        exec "${SCRIPT_DIR}/build-ios.sh" --simulator-arm64 "${BUILD_ARGS[@]}"
        ;;
    x86_64-apple-ios-sim)
        echo "--- :iphone: Building PyTorch for iOS simulator (Intel)"
        exec "${SCRIPT_DIR}/build-ios.sh" --simulator "${BUILD_ARGS[@]}"
        ;;
    arm64_32-apple-watchos)
        echo "--- :watch: Building PyTorch for watchOS"
        exec "${SCRIPT_DIR}/build-ios.sh" --watchos "${BUILD_ARGS[@]}"
        ;;

    # Android targets
    aarch64-linux-android)
        echo "--- :android: Building PyTorch for Android arm64-v8a"
        exec "${SCRIPT_DIR}/build-android.sh" --abi arm64-v8a "${BUILD_ARGS[@]}"
        ;;
    armv7-linux-androideabi)
        echo "--- :android: Building PyTorch for Android armeabi-v7a"
        exec "${SCRIPT_DIR}/build-android.sh" --abi armeabi-v7a "${BUILD_ARGS[@]}"
        ;;
    x86_64-linux-android)
        echo "--- :android: Building PyTorch for Android x86_64"
        exec "${SCRIPT_DIR}/build-android.sh" --abi x86_64 "${BUILD_ARGS[@]}"
        ;;
    i686-linux-android)
        echo "--- :android: Building PyTorch for Android x86"
        exec "${SCRIPT_DIR}/build-android.sh" --abi x86 "${BUILD_ARGS[@]}"
        ;;

    # Linux targets
    x86_64-unknown-linux-gnu)
        echo "--- :penguin: Building PyTorch for Linux x86_64"
        exec "${SCRIPT_DIR}/build-linux.sh" --target "${TARGET}" "${BUILD_ARGS[@]}"
        ;;
    aarch64-unknown-linux-gnu)
        echo "--- :penguin: Building PyTorch for Linux ARM64"
        exec "${SCRIPT_DIR}/build-linux.sh" --target "${TARGET}" "${BUILD_ARGS[@]}"
        ;;

    # Windows targets
    x86_64-pc-windows-msvc)
        echo "--- :windows: Building PyTorch for Windows x64 (MSVC)"
        exec "${SCRIPT_DIR}/build-windows.sh" --arch x64 "${BUILD_ARGS[@]}"
        ;;
    i686-pc-windows-msvc)
        echo "--- :windows: Building PyTorch for Windows x86 (MSVC)"
        exec "${SCRIPT_DIR}/build-windows.sh" --arch x86 "${BUILD_ARGS[@]}"
        ;;

    *)
        echo -e "${RED}Error: Unknown target triple: ${TARGET}${NC}"
        echo ""
        echo "Run '$0 --help' to see available targets"
        exit 1
        ;;
esac
