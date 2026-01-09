#!/bin/bash
set -e

# Configuration
APP_NAME="MP4SoundReplacer"
DISPLAY_NAME="MP4 Sound Replacer"
BUNDLE_ID="com.toratora.mp4soundreplacer"
VERSION="1.0.0"

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGE_DIR="${PROJECT_ROOT}/MP4SoundReplacer"
BUILD_DIR="${PACKAGE_DIR}/.build/release"
OUTPUT_DIR="${PROJECT_ROOT}/build"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"

echo "=== Building ${DISPLAY_NAME} ==="
echo "Project root: ${PROJECT_ROOT}"

# Clean previous build
rm -rf "${APP_BUNDLE}"
mkdir -p "${OUTPUT_DIR}"

# Build release binary
echo "Building release binary..."
cd "${PACKAGE_DIR}"
swift build -c release

# Verify binary exists
if [ ! -f "${BUILD_DIR}/${APP_NAME}" ]; then
    echo "Error: Binary not found at ${BUILD_DIR}/${APP_NAME}"
    exit 1
fi

# Create .app bundle structure
echo "Creating app bundle structure..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
echo "Copying executable..."
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Copy Info.plist
echo "Copying Info.plist..."
cp "${PACKAGE_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/"

# Copy entitlements for reference
cp "${PACKAGE_DIR}/Entitlements/MP4SoundReplacer.entitlements" "${APP_BUNDLE}/Contents/Resources/"

# Copy app icon if exists
if [ -f "${PACKAGE_DIR}/Resources/AppIcon.icns" ]; then
    echo "Copying app icon..."
    cp "${PACKAGE_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
fi

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Code sign with entitlements (ad-hoc signing for development)
echo "Code signing..."
codesign --force --deep --sign - \
    --entitlements "${PACKAGE_DIR}/Entitlements/MP4SoundReplacer.entitlements" \
    "${APP_BUNDLE}"

# Verify
echo ""
echo "=== Build Complete ==="
echo "Output: ${APP_BUNDLE}"
echo ""
echo "To run the app:"
echo "  open \"${APP_BUNDLE}\""
echo ""
echo "To verify code signature:"
echo "  codesign -dv --verbose=4 \"${APP_BUNDLE}\""
