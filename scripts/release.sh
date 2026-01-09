#!/bin/bash
set -e

# Master release script
# Builds the app and creates DMG

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo "  Audio Remux - Release Build"
echo "=========================================="
echo ""

# Step 1: Generate icon (if needed)
if [ ! -f "${SCRIPT_DIR}/../AudioRemux/Resources/AppIcon.icns" ]; then
    echo "Step 1: Generating app icon..."
    swift "${SCRIPT_DIR}/generate-icon.swift"
else
    echo "Step 1: App icon exists, skipping generation"
fi

echo ""

# Step 2: Build app bundle
echo "Step 2: Building app bundle..."
"${SCRIPT_DIR}/build-app.sh"

echo ""

# Step 3: Create DMG
echo "Step 3: Creating DMG..."
"${SCRIPT_DIR}/create-dmg.sh"

echo ""
echo "=========================================="
echo "  Release build complete!"
echo "=========================================="
echo ""
echo "Outputs:"
echo "  App: build/AudioRemux.app"
echo "  DMG: build/AudioRemux-1.0.0.dmg"
