#!/bin/bash

# Fuzzy Macro installer for macOS 10.12+ (Intel and Apple Silicon).
#
#   fuzzy_installer.command [stable|beta|main]
#
#   stable  the newest GitHub release marked Latest (default)
#   beta    the newest GitHub release, including pre-releases
#   main    the latest commit on main

REPO="Fuzzy-Team/Fuzzy-Macro"
APP_DIR="$HOME/Downloads/Fuzzy Macro"
CHANNEL="${1:-stable}"
WORK_DIR=""

# Temp files live next to the install so moving folders into place is a rename.
cleanup() {
    [[ -n "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT

say() {
    printf '\033[1;35m%s\033[0m\n' "$1"
}

# One-button dialog. "\n" in a message is a new line.
gui() {
    local msg=${1//\"/\\\"}
    osascript -e "display dialog \"$msg\" buttons {\"Continue\"} default button \"Continue\"" >/dev/null 2>&1 || true
}

fail() {
    printf '\033[31;1m%s\033[0m\n' "$1" >&2
    gui "$1"
    exit 1
}

version_at_least() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# --- REQUIREMENTS ---
os_ver=$(sw_vers -productVersion)
if ! version_at_least "$os_ver" "10.12"; then
    fail "Fuzzy Macro needs macOS 10.12 or later. You have $os_ver."
fi
if [[ "$(arch)" == "arm64" ]] && ! version_at_least "$os_ver" "13.0"; then
    fail "Apple Silicon Macs need macOS 13 (Ventura) or later. You have $os_ver."
fi

# --- PICK THE VERSION ---
release_tags() {
    curl -fsSL --retry 2 "https://api.github.com/repos/$REPO/$1" |
        sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p'
}

case "$CHANNEL" in
    stable)
        VERSION=$(release_tags "releases/latest" | head -n1)
        ;;
    beta)
        # Releases come newest first. Skip non-version helper releases such as "_gh-imgup".
        VERSION=$(release_tags "releases?per_page=30" | grep -v '^_' | head -n1)
        ;;
    main)
        VERSION="main"
        ;;
    *)
        fail "Unknown channel \"$CHANNEL\". Use stable, beta or main."
        ;;
esac
[[ -n "$VERSION" ]] || fail "Could not find a Fuzzy Macro release on GitHub. Check your internet connection and try again."

if [[ "$VERSION" == "main" ]]; then
    ZIP_URL="https://github.com/$REPO/archive/refs/heads/main.zip"
else
    ZIP_URL="https://github.com/$REPO/archive/refs/tags/$VERSION.zip"
fi

# --- DOWNLOAD ---
say "Downloading Fuzzy Macro $VERSION..."
mkdir -p "$(dirname "$APP_DIR")"
WORK_DIR=$(mktemp -d "$(dirname "$APP_DIR")/.fuzzy_install.XXXXXX") || fail "Could not create a temporary folder in $(dirname "$APP_DIR")."

curl -fL --retry 3 --connect-timeout 20 -# -o "$WORK_DIR/macro.zip" "$ZIP_URL" ||
    fail "Could not download Fuzzy Macro $VERSION. Check your internet connection and try again."
unzip -q "$WORK_DIR/macro.zip" -d "$WORK_DIR/extract" || fail "Could not unzip the Fuzzy Macro download."

# The zip holds one folder (Fuzzy-Macro-<version>).
NEW_DIR=$(find "$WORK_DIR/extract" -mindepth 1 -maxdepth 1 -type d | head -n1)
[[ -f "$NEW_DIR/install_dependencies.command" ]] ||
    fail "install_dependencies.command is missing from Fuzzy Macro $VERSION."

# --- INSTALL ---
# An older install is moved to the Trash. Your profiles, patterns and data carry over.
if [[ -d "$APP_DIR" ]]; then
    say "Keeping your profiles, patterns and data from the existing install..."
    for rel in settings/profiles src/data/user src/data/models; do
        [[ -d "$APP_DIR/$rel" ]] || continue
        rm -rf "$NEW_DIR/$rel"
        mkdir -p "$(dirname "$NEW_DIR/$rel")"
        mv "$APP_DIR/$rel" "$NEW_DIR/$rel"
    done
    # Patterns: keep yours and add the built-in ones you don't have yet.
    if [[ -d "$APP_DIR/settings/patterns" ]]; then
        cp -Rn "$NEW_DIR/settings/patterns/." "$APP_DIR/settings/patterns/" 2>/dev/null || true
        rm -rf "$NEW_DIR/settings/patterns"
        mv "$APP_DIR/settings/patterns" "$NEW_DIR/settings/patterns"
    fi
    mkdir -p "$HOME/.Trash"
    mv "$APP_DIR" "$HOME/.Trash/Fuzzy Macro $(date +%Y%m%d-%H%M%S)"
fi
mv "$NEW_DIR" "$APP_DIR" || fail "Could not install Fuzzy Macro into $APP_DIR."

# Downloads are quarantined, which blocks the .so files with "Permission denied".
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -type f \( -name "*.command" -o -name "*.sh" -o -name "*.so" -o -name "*.dylib" \) -exec chmod +x {} +

# --- PYTHON AND LIBRARIES ---
# install_dependencies.command installs the right Python for this Mac and sets up the libraries.
# It comes from the release just downloaded, not main, so the libraries match the code.
say "Installing Python and libraries..."
(cd "$APP_DIR" && bash "./install_dependencies.command") ||
    fail "Installing the libraries failed. Scroll up in Terminal to see the error, then run this installer again."

# --- DESKTOP SHORTCUT ---
say "Creating a desktop shortcut..."
WRAPPER="$HOME/Desktop/Fuzzy Macro Shortcut.command"
cat > "$WRAPPER" <<EOF
#!/bin/bash
chmod +x "$APP_DIR/run_macro.command"
open -a Terminal "$APP_DIR/run_macro.command"
EOF
chmod +x "$WRAPPER"

# --- DISPLAY AND KEYBOARD ---
defaults write com.apple.ColorSync CalibratorTargetProfile -string "sRGB IEC61966-2.1"

if ! defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q 'KeyboardLayout Name" = "\{0,1\}ABC'; then
    defaults write com.apple.HIToolbox AppleEnabledInputSources -array-add '{
        InputSourceKind = "Keyboard Layout";
        "KeyboardLayout ID" = 252;
        "KeyboardLayout Name" = "ABC";
    }'
fi

# --- PERMISSIONS ---
gui "Last step: Terminal permissions.\n\nSystem Settings will open four times. Each time, turn Terminal on (add it with + if it isn't listed), then click Continue."

grant_permission() {
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_$1"
    gui "Turn Terminal on under $2, then click Continue."
}

grant_permission "AllFiles" "Full Disk Access"
grant_permission "Accessibility" "Accessibility"
grant_permission "ScreenCapture" "Screen Recording"
grant_permission "ListenEvent" "Input Monitoring"

# --- DONE ---
gui "Fuzzy Macro $VERSION is installed.\n\nOpen it from the shortcut on your Desktop.\n\nBefore the first run, make sure your display color profile is sRGB IEC61966-2.1 and the ABC keyboard is selected. The docs show how: https://www.fuzzymacro.com/docs"
echo "Fuzzy Macro $VERSION installed at $APP_DIR"
exit 0
