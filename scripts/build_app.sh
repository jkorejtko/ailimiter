#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/dist/AILimiter.app"
BUILD_ARCH="${ARCH:-$(uname -m)}"
MODE="${1:-build}"

case "$MODE" in
    build|run|install) ;;
    *) echo "Usage: $0 [build|run|install]" >&2; exit 2 ;;
esac
case "$BUILD_ARCH" in
    arm64|x86_64) ;;
    *) echo "Unsupported architecture: $BUILD_ARCH" >&2; exit 2 ;;
esac

# Use the selected Xcode/Command Line Tools and the package's compiler settings.
cd "$PROJECT_DIR"
swift build --configuration release --arch "$BUILD_ARCH"
BIN_DIR="$(swift build --configuration release --arch "$BUILD_ARCH" --show-bin-path)"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/AILimiter" "$APP_BUNDLE/Contents/MacOS/AILimiter"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/"
chmod +x "$APP_BUNDLE/Contents/MacOS/AILimiter"

# Local ad-hoc signing; this does not sandbox or notarize the application.
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"
echo "Built $APP_BUNDLE ($BUILD_ARCH; local ad-hoc signature)"

if [ "$MODE" = "run" ]; then
    open "$APP_BUNDLE"
elif [ "$MODE" = "install" ]; then
    ditto "$APP_BUNDLE" "/Applications/AILimiter.app"
    echo "Installed /Applications/AILimiter.app"
fi
