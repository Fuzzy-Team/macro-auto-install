#!/bin/bash

# -------------------------------
# Existance Macro Installer
# macOS 13+ / Apple Silicon (M1–M4)
# -------------------------------

# GUI helper
gui() {
    osascript -e "display dialog \"$1\" buttons {\"Continue\"} default button \"Continue\""
}

# --- REQUIREMENTS CHECK ---
gui "Welcome to the Existance Macro installer.\n\nClick Continue to run compatibility checks."

# macOS version
macos_major=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$macos_major" -lt 13 ]]; then
    osascript -e 'display dialog "This installer requires macOS 13 or later." buttons {"OK"}'
    exit 1
fi

# Apple Silicon check
chip=$(sysctl -n machdep.cpu.brand_string)
if [[ "$chip" != *"Apple"* ]]; then
    osascript -e 'display dialog "This installer requires an Apple Silicon Mac (M1–M4)." buttons {"OK"}'
    exit 1
fi

# --- PYTHON CHECK ---
gui "Checking for Python 3..."

if ! command -v python3 >/dev/null 2>&1; then
    gui "Python 3 is not installed. The installer will now download and install Python from python.org."

    PYTHON_PKG="python-latest.pkg"
    curl -L -o "$PYTHON_PKG" "https://www.python.org/ftp/python/3.12.2/python-3.12.2-macos11.pkg"
    sudo installer -pkg "$PYTHON_PKG" -target /
    rm "$PYTHON_PKG"
else
    gui "Python 3 is already installed."
fi

# --- INSTALLER VENV SCRIPT ---
gui "Running virtual environment setup..."

bash -c "$(curl -fsSL https://raw.githubusercontent.com/existancepy/bss-macro-py-easy-install/refs/heads/main/virtual-env-install)"

# --- DOWNLOAD MACRO ZIP ---
gui "Downloading the Existance Macro package..."

TMP_ZIP="/tmp/existance_macro.zip"
curl -L -o "$TMP_ZIP" "https://github.com/existancepy/bss-macro-py/archive/refs/heads/main.zip"

# --- SETUP USER FOLDER ---
gui "Installing Existance Macro into your home folder..."

APP_DIR="$HOME/Existance Macro"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
unzip -o "$TMP_ZIP" -d "$APP_DIR"
rm "$TMP_ZIP"

# Move inner folder up one level
inner=$(find "$APP_DIR" -maxdepth 1 -type d -name "bss-macro-py-main")
mv "$inner"/* "$APP_DIR"
rm -rf "$inner"

# Remove quarantine attributes (fix Permission denied on .so files)
xattr -dr com.apple.quarantine "$APP_DIR"
chmod -R +x "$APP_DIR"

# --- DESKTOP SHORTCUT (Wrapper Script) ---
gui "Creating a desktop shortcut for Existance Macro..."

WRAPPER="$HOME/Desktop/Existance Macro Shortcut.command"
REAL_CMD="$APP_DIR/e_macro.command"

cat > "$WRAPPER" <<EOF
#!/bin/bash
cd "$APP_DIR"
chmod +x "$REAL_CMD"
open -a Terminal "$REAL_CMD"
EOF

chmod +x "$WRAPPER"

# --- CHECK / INSTALL CHROME ---
if [ -d "/Applications/Google Chrome.app" ]; then
    gui "Google Chrome is already installed. Skipping Chrome installation."
else
    gui "Google Chrome is not installed. The installer will download and install it."

    dmg="/tmp/chrome.dmg"
    curl -L -o "$dmg" "https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg"
    hdiutil mount "$dmg"
    sudo cp -r "/Volumes/Google Chrome/Google Chrome.app" /Applications/
    hdiutil unmount "/Volumes/Google Chrome"
    rm "$dmg"
fi

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
