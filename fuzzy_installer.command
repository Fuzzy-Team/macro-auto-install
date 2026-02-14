#!/bin/bash

# -------------------------------
# Fuzzy Macro Installer
# macOS 10.12+ / Intel or Apple Silicon (M1–M4)
# -------------------------------

# GUI helper
gui() {
    osascript -e "display dialog \"$1\" buttons {\"Continue\"} default button \"Continue\""
}

# --- REQUIREMENTS CHECK ---
gui "Welcome to the Fuzzy Macro installer.\n\nClick Continue to run compatibility checks."

# macOS version (require 10.12+)
product_version=$(sw_vers -productVersion)
major=$(echo "$product_version" | cut -d. -f1)
minor=$(echo "$product_version" | cut -d. -f2)
if [[ "$major" -ge 11 ]] || { [[ "$major" -eq 10 ]] && [[ -n "$minor" ]] && [[ "$minor" -ge 12 ]]; }; then
    : # macOS version OK (10.12+ or 11+)
else
    osascript -e 'display dialog "This installer requires macOS 10.12 or later." buttons {"OK"}'
    exit 1
fi

# Detect architecture (Intel or Apple Silicon)
arch=$(uname -m)
if [[ "$arch" == "arm64" ]]; then
    ARCH="arm64"
    gui "Detected Apple Silicon (arm64)."
else
    ARCH="x86_64"
    gui "Detected Intel (x86_64)."
fi

# --- PYTHON CHECK ---
gui "Checking for Python 3..."

if ! command -v python3 >/dev/null 2>&1; then
    gui "Python 3 is not installed. The installer will attempt to provide a suitable installer from python.org."

    # For macOS 11+ we can use the macos11 universal installer; older 10.12-10.15 systems
    # may not be compatible with the latest python.org pkg. In that case open the downloads page
    # so the user can choose a compatible build.
    if [[ "$major" -ge 11 ]]; then
        PYTHON_PKG="python-latest.pkg"
        curl -L -o "$PYTHON_PKG" "https://www.python.org/ftp/python/3.9.8/python-3.9.8-macos11.pkg"
        sudo installer -pkg "$PYTHON_PKG" -target /
        rm "$PYTHON_PKG"
    # Install old python installer on old devices
    else
        PYTHON_PKG="python-latest.pkg"
        curl -L -o "$PYTHON_PKG" "https://www.python.org/ftp/python/3.9.8/python-3.9.8-macosx10.9.pkg"
        sudo installer -pkg "$PYTHON_PKG" -target /
        rm "$PYTHON_PKG"
    fi
else
    gui "Python 3 is already installed."
fi

# --- INSTALLER VENV SCRIPT ---
gui "Running virtual environment setup..."

bash -c "$(curl -fsSL https://raw.githubusercontent.com/Fuzzy-Team/Fuzzy-Macro/refs/heads/main/install_dependencies.command)"


# --- DOWNLOAD MACRO ZIP (by latest tag) ---
gui "Fetching latest Fuzzy Macro version..."

TMP_ZIP="/tmp/fuzzy_macro.zip"

is_prerelease_tag() {
    local tag="$1"
    [[ "$tag" == *-* ]] && return 0
    [[ "$tag" == *alpha* || "$tag" == *beta* || "$tag" == *rc* || "$tag" == *pre* ]] && return 0
    return 1
}

fetch_latest_non_prerelease_tag() {
    local release_api tags_api tag
    release_api="https://api.github.com/repos/Fuzzy-Team/Fuzzy-Macro/releases/latest"
    tag=$(curl -fsSL "$release_api" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
    if [[ -n "$tag" ]] && ! is_prerelease_tag "$tag"; then
        printf '%s' "$tag"
        return 0
    fi

    tags_api="https://api.github.com/repos/Fuzzy-Team/Fuzzy-Macro/tags?per_page=100"
    while read -r tag; do
        [[ -z "$tag" ]] && continue
        if ! is_prerelease_tag "$tag"; then
            printf '%s' "$tag"
            return 0
        fi
    done < <(curl -fsSL "$tags_api" | sed -n 's/.*"name":[[:space:]]*"\([^"]*\)".*/\1/p')

    return 1
}

if ! LATEST_VERSION=$(fetch_latest_non_prerelease_tag); then
    gui "Failed to fetch latest non-prerelease tag. Aborting."
    exit 1
fi

gui "Downloading Fuzzy Macro version $LATEST_VERSION..."
ZIP_URL="https://github.com/Fuzzy-Team/Fuzzy-Macro/archive/refs/tags/${LATEST_VERSION}.zip"
curl -L -o "$TMP_ZIP" "$ZIP_URL"

# --- SETUP USER FOLDER ---
gui "Installing Fuzzy Macro into your home folder..."

APP_DIR="$HOME/Downloads/Fuzzy Macro"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
unzip -o "$TMP_ZIP" -d "$APP_DIR"
rm "$TMP_ZIP"

# Move inner folder up one level (tag zips use Fuzzy-Macro-$LATEST_VERSION)
inner=$(find "$APP_DIR" -maxdepth 1 -type d -name "Fuzzy-Macro-*")
mv "$inner"/* "$APP_DIR"
rm -rf "$inner"

# Remove quarantine attributes (fix Permission denied on .so files)
xattr -dr com.apple.quarantine "$APP_DIR"
chmod -R +x "$APP_DIR"

# --- DESKTOP SHORTCUT (Wrapper Script) ---
gui "Creating a desktop shortcut for Fuzzy Macro..."

WRAPPER="$HOME/Desktop/Fuzzy Macro Shortcut.command"
REAL_CMD="$APP_DIR/run_macro.command"

cat > "$WRAPPER" <<EOF
#!/bin/bash
cd "$APP_DIR"
chmod +x "$REAL_CMD"
open -a Terminal "$REAL_CMD"
EOF

chmod +x "$WRAPPER"

# --- DISPLAY COLOR PROFILE ---
gui "Setting your display color profile to sRGB IEC61966-2.1..."
defaults write com.apple.ColorSync CalibratorTargetProfile -string "sRGB IEC61966-2.1"

# --- KEYBOARD LAYOUT ---
gui "Setting keyboard input source to ABC..."

osascript <<EOF
tell application "System Preferences"
    reveal anchor "InputSources" of pane id "com.apple.preference.keyboard"
end tell
delay 1
EOF

defaults write com.apple.HIToolbox AppleEnabledInputSources -array-add '{
    InputSourceKind = "Keyboard Layout";
    "KeyboardLayout ID" = 252;
    "KeyboardLayout Name" = "ABC";
}'

# --- PERMISSIONS SECTION ---
gui "Next step: Terminal permissions.\n\nSystem Settings will open for each category.\nPlease enable Terminal manually if needed."

open_privacy() {
    local page=$1
    local title=$2
    gui "Opening: $title\n\nEnable Terminal in this category if it appears."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_$page"
    sleep 3
}

open_privacy "AllFiles" "Full Disk Access"
open_privacy "Accessibility" "Accessibility"
open_privacy "ScreenCapture" "Screen Recording"
open_privacy "ListenEvent" "Input Monitoring"

gui "Once you have enabled the permissions, click Continue."

# --- DONE ---
gui "Installation complete!\n\nYou can now launch the macro from the Desktop shortcut.\nIf Terminal prompts for permissions on first run, grant them."

exit 0
