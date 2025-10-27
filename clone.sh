#!/bin/bash
#
# clone.sh - Clone PyTorch repository at a specific tag
#
# Usage:
#   ./clone.sh --tag v2.1.0
#

set -e

echo "--- Cloning PyTorch repository and submodules"

# Windows: Add MSYS2 to PATH and enable long paths
if [ -d "/c/msys2/usr/bin" ]; then
    export PATH=/c/msys2/usr/bin:$PATH
    git config --system core.longpaths true || true  # Don't fail if already set or no permission
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
TAG=""
USE_CACHE=0
CREATE_CACHE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)
            TAG="$2"
            shift 2
            ;;
        --cache)
            CREATE_CACHE=1
            shift
            ;;
        --from-cache)
            USE_CACHE=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 --tag <version> [options]"
            echo ""
            echo "Clone PyTorch repository at a specific tag with minimal history."
            echo ""
            echo "Arguments:"
            echo "  --tag <version>    Git tag to clone (e.g., v2.1.0, v2.2.0)"
            echo "  --cache            After cloning, create pytorch-<TAG>.src.tar.gz archive"
            echo "  --from-cache       Extract from pytorch-<TAG>.src.tar.gz instead of cloning"
            echo ""
            echo "Examples:"
            echo "  $0 --tag v2.1.0"
            echo "  $0 --tag v2.1.0 --cache              # Clone and create cache"
            echo "  $0 --tag v2.1.0 --from-cache         # Restore from cache"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Validate tag is provided
if [ -z "$TAG" ]; then
    echo -e "${RED}Error: --tag is required${NC}"
    echo "Run '$0 --help' for usage information"
    exit 1
fi

PYTORCH_DIR="pytorch"
PYTORCH_REPO="https://github.com/pytorch/pytorch.git"
ARCHIVE_NAME="pytorch-${TAG}.src.tar.gz"

# Handle cache restoration
if [ $USE_CACHE -eq 1 ]; then
    if [ ! -f "$ARCHIVE_NAME" ]; then
        echo -e "${RED}Error: Cache archive not found: $ARCHIVE_NAME${NC}"
        exit 1
    fi

    if [ -d "$PYTORCH_DIR" ]; then
        echo -e "${RED}Error: pytorch directory already exists${NC}"
        exit 1
    fi

    echo -e "${GREEN}Extracting from cache: $ARCHIVE_NAME${NC}"
    tar -xzf "$ARCHIVE_NAME"
    echo ""
    echo -e "${GREEN}PyTorch restored from cache at ${TAG}${NC}"
    echo -e "${GREEN}PyTorch is ready at: $(pwd)/$PYTORCH_DIR${NC}"
    echo -e "${GREEN}Version: ${TAG}${NC}"
    echo ""
    exit 0
fi

# Clone or update PyTorch
if [ ! -d "$PYTORCH_DIR" ]; then
    echo -e "${GREEN}Cloning PyTorch at tag ${TAG}...${NC}"
    git clone --depth 1 --branch "$TAG" "$PYTORCH_REPO" "$PYTORCH_DIR"

    cd "$PYTORCH_DIR"

    echo -e "${YELLOW}Initializing submodules...${NC}"
    git submodule update --init --recursive --depth 1

    echo -e "${YELLOW}Fetching optional submodules (eigen)...${NC}"
    python3 tools/optional_submodules.py checkout_eigen

    echo -e "${GREEN}PyTorch cloned successfully at ${TAG}${NC}"
else
    echo -e "${YELLOW}PyTorch directory already exists, updating to ${TAG}...${NC}"

    cd "$PYTORCH_DIR"

    # Fetch the specific tag
    echo -e "${YELLOW}Fetching tag ${TAG}...${NC}"
    git fetch --depth 1 origin "tag" "$TAG"

    # Checkout the tag
    echo -e "${YELLOW}Checking out ${TAG}...${NC}"
    git checkout "$TAG"

    # Update submodules
    echo -e "${YELLOW}Updating submodules...${NC}"
    git submodule update --init --recursive --depth 1

    echo -e "${YELLOW}Fetching optional submodules (eigen)...${NC}"
    python3 tools/optional_submodules.py checkout_eigen

    echo -e "${GREEN}PyTorch updated to ${TAG}${NC}"
fi

echo ""
echo -e "${GREEN}PyTorch is ready at: $(pwd)${NC}"
echo -e "${GREEN}Version: ${TAG}${NC}"
echo ""

# Create cache archive if requested
if [ $CREATE_CACHE -eq 1 ]; then
    cd ..
    echo -e "${YELLOW}Creating cache archive: $ARCHIVE_NAME${NC}"
    tar --exclude='.git' -czf "$ARCHIVE_NAME" "$PYTORCH_DIR/"
    echo -e "${GREEN}Cache archive created: $ARCHIVE_NAME${NC}"
    echo ""
fi
