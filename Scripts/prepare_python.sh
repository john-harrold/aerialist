#!/bin/bash
# prepare_python.sh
#
# Downloads a standalone, relocatable Python distribution (python-build-standalone)
# and installs pdf2docx into it. The result is a self-contained Python directory
# that can be embedded in the Spindrift app bundle.
#
# Usage:
#   ./Scripts/prepare_python.sh
#
# Output:
#   Spindrift/Spindrift/Resources/python/  - ready-to-embed Python distribution
#
# Requirements:
#   - curl, tar, zstd (brew install zstd)
#   - ~500MB disk space during build, ~150MB final

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/python-bundle"
OUTPUT_DIR="$PROJECT_DIR/Spindrift/Spindrift/Resources/python"

# Python version and release
PYTHON_VERSION="3.12.12"
RELEASE="20260211"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    PLATFORM="aarch64-apple-darwin"
elif [ "$ARCH" = "x86_64" ]; then
    PLATFORM="x86_64-apple-darwin"
else
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
fi

FLAVOR="install_only_stripped"
FILENAME="cpython-${PYTHON_VERSION}+${RELEASE}-${PLATFORM}-${FLAVOR}.tar.gz"
URL="https://github.com/astral-sh/python-build-standalone/releases/download/${RELEASE}/${FILENAME}"

echo "=== Spindrift Python Bundle Preparation ==="
echo "Python:   $PYTHON_VERSION"
echo "Platform: $PLATFORM"
echo "Output:   $OUTPUT_DIR"
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Download Python
echo "Step 1/6: Downloading Python..."
if [ -f "$PROJECT_DIR/.build/${FILENAME}" ]; then
    echo "  Using cached download"
    cp "$PROJECT_DIR/.build/${FILENAME}" "$BUILD_DIR/"
else
    curl -L -o "$BUILD_DIR/${FILENAME}" "$URL"
    # Cache for future runs
    cp "$BUILD_DIR/${FILENAME}" "$PROJECT_DIR/.build/${FILENAME}"
fi

# Step 2: Extract
echo "Step 2/6: Extracting..."
cd "$BUILD_DIR"
tar xf "${FILENAME}"
PYTHON_DIR="$BUILD_DIR/python"

# Verify python3 exists
if [ ! -f "$PYTHON_DIR/bin/python3" ]; then
    # Some releases put it in install/
    if [ -f "$PYTHON_DIR/install/bin/python3" ]; then
        PYTHON_DIR="$PYTHON_DIR/install"
    else
        echo "Error: python3 binary not found in extracted archive"
        ls -la "$BUILD_DIR/"
        exit 1
    fi
fi

echo "  Python binary: $PYTHON_DIR/bin/python3"
"$PYTHON_DIR/bin/python3" --version

# Step 3: Install pdf2docx
echo "Step 3/6: Installing pdf2docx and dependencies..."
"$PYTHON_DIR/bin/python3" -m pip install --quiet 'PyMuPDF<1.25' pdf2docx docx2pdf

# Verify installation
"$PYTHON_DIR/bin/python3" -c "from pdf2docx import Converter; print('  pdf2docx OK')"
"$PYTHON_DIR/bin/python3" -c "import docx2pdf; print('  docx2pdf OK')"

# Step 4: Strip unnecessary files to reduce size
echo "Step 4/6: Stripping unnecessary files..."
cd "$PYTHON_DIR"

# Remove stdlib modules not needed for pdf2docx
rm -rf lib/python*/test
rm -rf lib/python*/unittest
rm -rf lib/python*/idlelib
rm -rf lib/python*/tkinter
rm -rf lib/python*/turtledemo
rm -rf lib/python*/ensurepip
rm -rf lib/python*/lib2to3
rm -rf lib/python*/distutils
rm -rf lib/python*/pydoc_data
rm -rf lib/python*/sqlite3
rm -rf lib/python*/curses
# multiprocessing is needed by pdf2docx
rm -rf lib/python*/xmlrpc
rm -rf lib/python*/wsgiref
rm -rf lib/python*/turtle.py
rm -rf lib/python*/doctest.py
rm -rf lib/python*/pdb.py

# Remove .pyc files and __pycache__
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true

# Remove pip/setuptools
rm -rf lib/python*/site-packages/pip
rm -rf lib/python*/site-packages/pip-*.dist-info
rm -rf lib/python*/site-packages/setuptools
rm -rf lib/python*/site-packages/setuptools-*.dist-info

# Note: cv2 dylibs have deep interdependencies (ffmpeg, X11, etc.)
# and cannot be selectively stripped without breaking cv2.
# Keep all dylibs intact (~75MB).

# Remove OpenCV Haar cascade data (not needed for pdf2docx)
rm -rf lib/python*/site-packages/cv2/data

# Remove .pyi stubs and license files from cv2
rm -f lib/python*/site-packages/cv2/*.pyi
rm -f lib/python*/site-packages/cv2/LICENSE*

# Remove dist-info directories (save ~1MB)
find lib/python*/site-packages -name "*.dist-info" -type d -exec rm -rf {} + 2>/dev/null || true

# Remove unnecessary shared libraries
rm -rf lib/python*/_sysconfigdata_*.py

# Calculate size
SIZE=$(du -sh "$PYTHON_DIR" | cut -f1)
echo "  Stripped size: $SIZE"

# Step 5: Ad-hoc codesign everything
echo "Step 5/6: Codesigning binaries..."
find "$PYTHON_DIR" \( -name "*.so" -o -name "*.dylib" -o -name "python3*" -type f \) | while read -r f; do
    codesign --force --sign - "$f" 2>/dev/null || true
done
echo "  Codesigning complete"

# Step 6: Copy to output
echo "Step 6/6: Copying to project..."
rm -rf "$OUTPUT_DIR"
cp -R "$PYTHON_DIR" "$OUTPUT_DIR"

# Final size
FINAL_SIZE=$(du -sh "$OUTPUT_DIR" | cut -f1)
echo ""
echo "=== Done ==="
echo "Python bundle ready at: $OUTPUT_DIR"
echo "Bundle size: $FINAL_SIZE"
echo ""
echo "To test:"
echo "  $OUTPUT_DIR/bin/python3 -c 'from pdf2docx import Converter; print(\"OK\")'"
