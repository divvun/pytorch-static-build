#!/bin/bash
#
# download-cache.sh - Download cached PyTorch source tarball
#
# Usage:
#   ./download-cache.sh
#

set -e

# Add MSYS2 to PATH if present
if [ -d "/c/msys2/usr/bin" ]; then
    export PATH=/c/msys2/usr/bin:$PATH
fi

PYTORCH_VERSION="v2.8.0"
PYTORCH_URL="https://github.com/divvun/pytorch-static-build/releases/download/pytorch%2F${PYTORCH_VERSION}/pytorch-${PYTORCH_VERSION}.src.tar.gz"
TARBALL="pytorch.tar.gz"

echo "--- Downloading cached PyTorch ${PYTORCH_VERSION}"

# Clean up any existing pytorch directory
rm -rf pytorch

# Download tarball
curl -sSfL "${PYTORCH_URL}" -o "${TARBALL}"

# Extract (use bsdtar on Windows because msys tar is broken)
if [ "$WINDOWS" = "1" ]; then
    bsdtar -xf "${TARBALL}"
else
    tar xf "${TARBALL}"
fi

# Clean up tarball
rm "${TARBALL}"

echo "PyTorch ${PYTORCH_VERSION} extracted successfully"
