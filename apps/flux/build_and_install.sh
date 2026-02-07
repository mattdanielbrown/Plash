#!/bin/bash

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
APP_NAME="Flux"
SCHEME="Flux"
PROJECT="Flux.xcodeproj"
CONFIGURATION="Release"
INSTALL_DIR="/Applications"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION=$(grep 'MARKETING_VERSION' "$SCRIPT_DIR/Config.xcconfig" | cut -d'=' -f2 | tr -d ' ')
BUILD_NUM=$(grep 'CURRENT_PROJECT_VERSION' "$SCRIPT_DIR/Config.xcconfig" | cut -d'=' -f2 | tr -d ' ')
DMG_DIR="$SCRIPT_DIR/dist"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

# ── Helpers ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step()  { echo -e "\n${CYAN}${BOLD}▸ $1${NC}"; }
ok()    { echo -e "  ${GREEN}✓ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $1${NC}"; }
fail()  { echo -e "  ${RED}✗ $1${NC}"; exit 1; }

usage() {
    echo -e "${BOLD}Usage:${NC} $0 [options]"
    echo ""
    echo "  Options:"
    echo "    --dmg         Build and package into a DMG (skip install)"
    echo "    --install     Build, kill, and install to /Applications (default)"
    echo "    --all         Build, install, and create DMG"
    echo "    --no-clean    Skip the clean step for faster rebuilds"
    echo "    --no-launch   Don't launch the app after installing"
    echo "    -h, --help    Show this help"
    echo ""
    exit 0
}

# ── Parse args ──────────────────────────────────────────────────────────────
MODE="install"
DO_CLEAN=true
DO_LAUNCH=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)       MODE="dmg"; shift ;;
        --install)   MODE="install"; shift ;;
        --all)       MODE="all"; shift ;;
        --no-clean)  DO_CLEAN=false; shift ;;
        --no-launch) DO_LAUNCH=false; shift ;;
        -h|--help)   usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo -e "${BOLD}${APP_NAME} v${VERSION} (${BUILD_NUM})${NC}"

# ── Build ───────────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"

CLEAN_ARG=""
if $DO_CLEAN; then
    CLEAN_ARG="clean"
fi

step "Syncing Fluid Simulation files..."
FLUID_SRC="$SCRIPT_DIR/../fluid"
FLUID_DST="$SCRIPT_DIR/Flux/FluidSimulation"
mkdir -p "$FLUID_DST"
cp "$FLUID_SRC/index.html" "$FLUID_DST/index.html"
cp "$FLUID_SRC/script.js" "$FLUID_DST/script.js"
cp "$FLUID_SRC/dat.gui.min.js" "$FLUID_DST/dat.gui.min.js"
ok "Synced Fluid Simulation files"

step "Building ${APP_NAME} (${CONFIGURATION})..."

BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    $CLEAN_ARG build \
    2>&1 | tail -5

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
    fail "Build product not found at $APP_PATH"
fi

ok "Built $APP_PATH"

# ── Install ─────────────────────────────────────────────────────────────────
do_install() {
    step "Stopping running ${APP_NAME}..."
    if pgrep -xq "$APP_NAME"; then
        killall "$APP_NAME" 2>/dev/null || true
        sleep 1
        # Force-kill if still alive
        if pgrep -xq "$APP_NAME"; then
            killall -9 "$APP_NAME" 2>/dev/null || true
            sleep 0.5
        fi
        ok "Killed running instance"
    else
        ok "No running instance found"
    fi

    step "Clearing app data for fresh install..."
    defaults delete com.stokedconsulting.Flux 2>/dev/null || true
    ok "Cleared app defaults"

    step "Installing to ${INSTALL_DIR}..."
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    cp -R "$APP_PATH" "${INSTALL_DIR}/${APP_NAME}.app"
    ok "Installed to ${INSTALL_DIR}/${APP_NAME}.app"

    if $DO_LAUNCH; then
        step "Launching ${APP_NAME}..."
        open "${INSTALL_DIR}/${APP_NAME}.app"
        ok "Launched"
    fi
}

# ── DMG ─────────────────────────────────────────────────────────────────────
do_dmg() {
    step "Creating DMG..."

    mkdir -p "$DMG_DIR"

    local staging="$BUILD_DIR/dmg-staging"
    local tmp_dmg="$BUILD_DIR/${APP_NAME}-tmp.dmg"
    local final_dmg="$DMG_DIR/$DMG_NAME"

    # Clean previous staging
    rm -rf "$staging"
    mkdir -p "$staging"

    # Copy app bundle
    cp -R "$APP_PATH" "$staging/${APP_NAME}.app"

    # Create Applications symlink for drag-to-install
    ln -s /Applications "$staging/Applications"

    # Remove old DMG if present
    rm -f "$tmp_dmg" "$final_dmg"

    # Create temporary read-write DMG
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$staging" \
        -ov \
        -format UDRW \
        "$tmp_dmg" \
        -quiet

    # Mount it to configure appearance
    local mount_dir
    mount_dir=$(hdiutil attach "$tmp_dmg" -readwrite -noverify -quiet | grep '/Volumes/' | tail -1 | awk '{print $3}')

    # Set DMG window appearance via .DS_Store
    # Position the window, set icon size, set background
    osascript <<EOF
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        delay 0.5
        set the bounds of container window to {100, 100, 640, 400}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "${APP_NAME}.app" of container window to {140, 150}
        set position of item "Applications" of container window to {400, 150}
        close
    end tell
end tell
EOF

    # Unmount
    hdiutil detach "$mount_dir" -quiet || hdiutil detach "$mount_dir" -force -quiet

    # Convert to compressed read-only DMG
    hdiutil convert "$tmp_dmg" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "$final_dmg" \
        -quiet

    # Clean up
    rm -f "$tmp_dmg"
    rm -rf "$staging"

    local size
    size=$(du -h "$final_dmg" | cut -f1 | tr -d ' ')
    ok "Created ${final_dmg} (${size})"
}

# ── Run ─────────────────────────────────────────────────────────────────────
case "$MODE" in
    install)
        do_install
        ;;
    dmg)
        do_dmg
        ;;
    all)
        do_install
        do_dmg
        ;;
esac

echo -e "\n${GREEN}${BOLD}Done!${NC}"
