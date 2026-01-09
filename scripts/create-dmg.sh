#!/bin/bash
set -e

# Configuration
APP_NAME="AudioRemux"
DISPLAY_NAME="Audio Remux"
VERSION="1.0.0"

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}.dmg"
DMG_TEMP="${BUILD_DIR}/dmg_temp"

echo "=== Creating DMG for ${DISPLAY_NAME} ==="

# Check if app exists
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "Error: App bundle not found at ${APP_BUNDLE}"
    echo "Please run build-app.sh first"
    exit 1
fi

# Clean previous DMG
rm -f "${DMG_PATH}"
rm -rf "${DMG_TEMP}"

# Create temp directory for DMG contents
mkdir -p "${DMG_TEMP}"

# Copy app to temp directory
echo "Copying app bundle..."
cp -R "${APP_BUNDLE}" "${DMG_TEMP}/"

# Create symbolic link to Applications folder
ln -s /Applications "${DMG_TEMP}/Applications"

# Calculate DMG size (app size + some buffer)
APP_SIZE=$(du -sm "${APP_BUNDLE}" | cut -f1)
DMG_SIZE=$((APP_SIZE + 20))

echo "Creating DMG (${DMG_SIZE}MB)..."

# Create DMG
hdiutil create \
    -volname "${DISPLAY_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

# Clean up
rm -rf "${DMG_TEMP}"

echo ""
echo "=== DMG Created ==="
echo "Output: ${DMG_PATH}"
echo "Size: $(du -h "${DMG_PATH}" | cut -f1)"
echo ""
echo "To install:"
echo "  1. Open ${DMG_NAME}.dmg"
echo "  2. Drag ${APP_NAME} to Applications"
