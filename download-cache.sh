#!/bin/bash
#
# download-cache.sh - Download cached PyTorch source tarball
#
# Usage:
#   ./download-cache.sh
#

set -e

PYTORCH_VERSION="v2.8.0"
PYTORCH_URL="https://github.com/divvun/pytorch-static-build/releases/download/pytorch%2F${PYTORCH_VERSION}/pytorch-${PYTORCH_VERSION}.src.tar.gz"
TARBALL="pytorch.tar.gz"

echo "--- Downloading cached PyTorch ${PYTORCH_VERSION}"

# Clean up any existing pytorch directory
rm -rf pytorch

# Download tarball
curl -sSfL "${PYTORCH_URL}" -o "${TARBALL}"

# Extract
tar xf "${TARBALL}"

# Clean up tarball
rm "${TARBALL}"

echo "PyTorch ${PYTORCH_VERSION} extracted successfully"
