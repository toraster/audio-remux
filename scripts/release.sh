#!/bin/bash
set -e

# Master release script
# Builds the app and creates DMG

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo "  MP4 Sound Replacer - Release Build"
echo "=========================================="
echo ""

# Step 1: Generate icon (if needed)
if [ ! -f "${SCRIPT_DIR}/../MP4SoundReplacer/Resources/AppIcon.icns" ]; then
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
echo "  App: build/MP4SoundReplacer.app"
echo "  DMG: build/MP4SoundReplacer-1.0.0.dmg"
