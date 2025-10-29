#!/bin/bash
#
# build-pytorch.sh - Unified PyTorch build script for all platforms
#
# Usage:
#   ./build-pytorch.sh --target <triple>           # Build for specified target
#   ./build-pytorch.sh --target aarch64-apple-darwin --debug
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
    echo "Build Options:"
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
    echo ""
    echo "Examples:"
    echo "  ./build-pytorch.sh --target aarch64-apple-darwin"
    echo "  ./build-pytorch.sh --target aarch64-apple-ios --debug"
    echo "  ./build-pytorch.sh --target aarch64-linux-android --vulkan"
    echo "  ./build-pytorch.sh --target x86_64-unknown-linux-gnu --distributed"
}

# Parse target flag and options
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

# Add PATH for Windows if needed
case "$TARGET" in
    *-windows-*)
        export PATH=$PATH:/c/msys2/usr/bin
        ;;
esac

# Route to appropriate build script based on target triple
case "$TARGET" in
    # macOS targets
    aarch64-apple-darwin|x86_64-apple-darwin)
        echo "--- :apple: Building PyTorch for macOS"
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
    x86_64-unknown-linux-gnu|aarch64-unknown-linux-gnu)
        echo "--- :penguin: Building PyTorch for Linux"
        exec "${SCRIPT_DIR}/build-linux.sh" --target "${TARGET}" "${BUILD_ARGS[@]}"
        ;;

    *)
        echo -e "${RED}Error: Unknown or unsupported target triple: ${TARGET}${NC}"
        echo ""
        echo "Run '$0 --help' to see available targets"
        exit 1
        ;;
esac
