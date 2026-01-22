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
    else
        gui "Automatic installer not available for your macOS version. A browser window will open to python.org; please download a Python 3 installer compatible with macOS 10.12+ (for example, a 3.8/3.9 build)."
        open "https://www.python.org/downloads/macos/"
    fi
else
    gui "Python 3 is already installed."
fi

# --- INSTALLER VENV SCRIPT ---
gui "Running virtual environment setup..."

bash -c "$(curl -fsSL https://raw.githubusercontent.com/Fuzzy-Team/Fuzzy-Macro/refs/heads/main/install_dependencies.command)"

# --- DOWNLOAD MACRO ZIP ---
gui "Downloading the Fuzzy Macro package..."

TMP_ZIP="/tmp/fuzzy_macro.zip"
curl -L -o "$TMP_ZIP" "https://github.com/Fuzzy-Team/Fuzzy-Macro/archive/refs/heads/main.zip"

# --- SETUP USER FOLDER ---
gui "Installing Fuzzy Macro into your home folder..."

APP_DIR="$HOME/Fuzzy Macro"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
unzip -o "$TMP_ZIP" -d "$APP_DIR"
rm "$TMP_ZIP"

# Move inner folder up one level
inner=$(find "$APP_DIR" -maxdepth 1 -type d -name "Fuzzy-Macro-main")
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
