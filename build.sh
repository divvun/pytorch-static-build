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
    echo "  ./build.sh --target x86_64-pc-windows-msvc --shared"
}

# Parse target flag
TARGET=""
BUILD_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --target)
            TARGET="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            # Pass through all other arguments
            BUILD_ARGS+=("$1")
            shift
            ;;
    esac
done

# Check if target was specified
if [ -z "$TARGET" ]; then
    echo -e "${RED}Error: --target flag is required${NC}"
    echo ""
    show_help
    exit 1
fi

# Determine which build script to use and what flags to pass
case "$TARGET" in
    # macOS targets
    aarch64-apple-darwin)
        echo -e "${GREEN}Building for macOS (Apple Silicon)${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-macos.sh" "${BUILD_ARGS[@]}"
        ;;
    x86_64-apple-darwin)
        echo -e "${GREEN}Building for macOS (Intel)${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-macos.sh" "${BUILD_ARGS[@]}"
        ;;

    # iOS targets
    aarch64-apple-ios)
        echo -e "${GREEN}Building for iOS device${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-ios.sh" --device "${BUILD_ARGS[@]}"
        ;;
    aarch64-apple-ios-sim)
        echo -e "${GREEN}Building for iOS simulator (Apple Silicon)${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-ios.sh" --simulator-arm64 "${BUILD_ARGS[@]}"
        ;;
    x86_64-apple-ios-sim)
        echo -e "${GREEN}Building for iOS simulator (Intel)${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-ios.sh" --simulator "${BUILD_ARGS[@]}"
        ;;
    arm64_32-apple-watchos)
        echo -e "${GREEN}Building for watchOS${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-ios.sh" --watchos "${BUILD_ARGS[@]}"
        ;;

    # Android targets
    aarch64-linux-android)
        echo -e "${GREEN}Building for Android arm64-v8a${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-android.sh" --abi arm64-v8a "${BUILD_ARGS[@]}"
        ;;
    armv7-linux-androideabi)
        echo -e "${GREEN}Building for Android armeabi-v7a${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-android.sh" --abi armeabi-v7a "${BUILD_ARGS[@]}"
        ;;
    x86_64-linux-android)
        echo -e "${GREEN}Building for Android x86_64${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-android.sh" --abi x86_64 "${BUILD_ARGS[@]}"
        ;;
    i686-linux-android)
        echo -e "${GREEN}Building for Android x86${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-android.sh" --abi x86 "${BUILD_ARGS[@]}"
        ;;

    # Linux targets
    x86_64-unknown-linux-gnu)
        echo -e "${GREEN}Building for Linux x86_64${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-linux.sh" "${BUILD_ARGS[@]}"
        ;;
    aarch64-unknown-linux-gnu)
        echo -e "${GREEN}Building for Linux ARM64${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-linux.sh" "${BUILD_ARGS[@]}"
        ;;

    # Windows targets
    x86_64-pc-windows-msvc)
        echo -e "${GREEN}Building for Windows x64 (MSVC)${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-windows.sh" --arch x64 "${BUILD_ARGS[@]}"
        ;;
    i686-pc-windows-msvc)
        echo -e "${GREEN}Building for Windows x86 (MSVC)${NC}"
        cd "${SCRIPT_DIR}/pytorch"
        exec "${SCRIPT_DIR}/build-windows.sh" --arch x86 "${BUILD_ARGS[@]}"
        ;;

    *)
        echo -e "${RED}Error: Unknown target triple: ${TARGET}${NC}"
        echo ""
        echo "Run '$0 --help' to see available targets"
        exit 1
        ;;
esac
