#!/bin/bash

# ==============================================================================
# SunnyLand WebAssembly Build Script
# ==============================================================================
# Prerequisites:
# - Emscripten SDK (emsdk) must be installed and activated in the current shell.
#   (source path/to/emsdk/emsdk_env.sh)
#
# Usage:
#   ./build_web.sh [clean]
#   - clean: Remove existing build directory before building.
# ==============================================================================

BUILD_DIR="build_web"

# Check if emcmake is available
if ! command -v emcmake &> /dev/null; then
    echo "Error: 'emcmake' not found. Please activate Emscripten SDK first."
    echo "Example: source ~/emsdk/emsdk_env.sh"
    exit 1
fi

# Clean build if requested
if [ "$1" == "clean" ]; then
    echo "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

# Create build directory
if [ ! -d "$BUILD_DIR" ]; then
    mkdir "$BUILD_DIR"
fi

# Navigate to build directory
cd "$BUILD_DIR" || exit

# Configure with CMake (using Emscripten toolchain)
echo "Configuring project..."
# -DCMAKE_BUILD_TYPE=Release: Optimize for size and speed
emcmake cmake .. -DCMAKE_BUILD_TYPE=Release

# Build
echo "Building project..."
emmake make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "========================================================"
echo "Build complete!"
echo "To run the game:"
echo "1. python3 -m http.server 8000 --directory build_web"
echo "2. Open http://localhost:8000/SunnyLand-Emscripten.html in your browser"
echo "========================================================"
