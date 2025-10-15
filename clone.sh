#!/bin/bash
#
# clone.sh - Clone PyTorch repository at a specific tag
#
# Usage:
#   ./clone.sh --tag v2.1.0
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
TAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)
            TAG="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 --tag <version>"
            echo ""
            echo "Clone PyTorch repository at a specific tag with minimal history."
            echo ""
            echo "Arguments:"
            echo "  --tag <version>    Git tag to clone (e.g., v2.1.0, v2.2.0)"
            echo ""
            echo "Examples:"
            echo "  $0 --tag v2.1.0"
            echo "  $0 --tag v2.2.0"
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

# Clone or update PyTorch
if [ ! -d "$PYTORCH_DIR" ]; then
    echo -e "${GREEN}Cloning PyTorch at tag ${TAG}...${NC}"
    git clone --depth 1 --branch "$TAG" "$PYTORCH_REPO" "$PYTORCH_DIR"

    cd "$PYTORCH_DIR"

    echo -e "${YELLOW}Initializing submodules...${NC}"
    git submodule update --init --recursive --depth 1

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

    echo -e "${GREEN}PyTorch updated to ${TAG}${NC}"
fi

echo ""
echo -e "${GREEN}PyTorch is ready at: $(pwd)${NC}"
echo -e "${GREEN}Version: ${TAG}${NC}"
echo ""
