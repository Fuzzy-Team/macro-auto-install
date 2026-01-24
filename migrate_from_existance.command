#!/bin/bash

# ---------------------------------------------
# Existance → Fuzzy Macro Migration Script
# macOS 10.12+ / Intel or Apple Silicon
# Note: This script is untested and is not advised at this current time.
# ---------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# ---------- GUI HELPERS ----------

gui() {
    osascript <<EOF
display dialog "$1" buttons {"Continue"} default button "Continue"
EOF
}

gui_yes_no() {
    osascript <<EOF >/dev/null
display dialog "$1" buttons {"Yes", "No"} default button "Yes"
EOF
}

gui_ok() {
    osascript <<EOF
display dialog "$1" buttons {"OK"} default button "OK"
EOF
}

# ---------- WELCOME ----------

gui "Welcome to the Existance → Fuzzy Macro Migration Tool.

This script will migrate your Existance Macro install to Fuzzy Macro.

A backup will be created before any changes."

# ---------- UNINSTALL OLD VENV ----------

if gui_yes_no "Do you want to uninstall the Existance Macro virtual environment?

This removes:
~/bss-macro-env

(Profiles are preserved)"; then
    rm -rf "$HOME/bss-macro-env"
    gui "Existance virtual environment removed."
else
    gui "Keeping Existance virtual environment."
fi

# ---------- SCRIPT LOCATION ----------

# Prompt user to select the macro folder so the script can be run remotely
choose_folder() {
    osascript <<EOF
tell application "Finder"
    set theFolder to (choose folder with prompt "Select your Existance Macro folder to migrate.")
    POSIX path of theFolder
end tell
EOF
}

# Try prompting the user for the macro folder first. If that fails, fall back to script location.
SCRIPT_DIR=""
if CHOSEN_DIR=$(choose_folder 2>/dev/null); then
    SCRIPT_DIR="${CHOSEN_DIR%/}"
fi

if [[ -z "$SCRIPT_DIR" || "$SCRIPT_DIR" == "/" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd 2>/dev/null || pwd)"
fi

# Set MIGRATION_SCRIPT only if this script exists as a readable file on disk.
# When executed via piping (curl | bash) there will be no on-disk script,
# so we leave MIGRATION_SCRIPT empty and avoid copying or deleting a non-existent file.
if [[ -f "$0" && -r "$0" ]]; then
    MIGRATION_SCRIPT="$(readlink -f "$0" 2>/dev/null || echo "$0")"
else
    MIGRATION_SCRIPT=""
fi

# ---------- SAFETY CHECKS ----------

if [[ -z "$SCRIPT_DIR" || "$SCRIPT_DIR" == "/" ]]; then
    gui_ok "ERROR: Unsafe script directory detected. Aborting."
    exit 1
fi

if [[ ! -d "$SCRIPT_DIR/settings" ]]; then
    gui_ok "ERROR: This script must be run from the Existance Macro folder.

Missing: settings/"
    exit 1
fi

if ! gui_yes_no "Confirm script location:

$SCRIPT_DIR

Is this your Existance Macro folder?"; then
    gui_ok "Move the script into the Existance Macro folder and try again."
    exit 1
fi

# ---------- BACKUP ----------

BACKUP_DIR="$SCRIPT_DIR/settings_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

COPIED=false
[[ -d "$SCRIPT_DIR/settings/profiles" ]] && cp -R "$SCRIPT_DIR/settings/profiles" "$BACKUP_DIR/" && COPIED=true
[[ -d "$SCRIPT_DIR/settings/patterns" ]] && cp -R "$SCRIPT_DIR/settings/patterns" "$BACKUP_DIR/" && COPIED=true

if $COPIED; then
    gui "Backup created at:

$BACKUP_DIR"
else
    BACKUP_DIR=""
    gui "No profiles or patterns found. Backup skipped."
fi

# ---------- TEMP WORKSPACE ----------

TMP_ROOT="$(mktemp -d /tmp/fuzzy_migration.XXXXXX)"
TMP_PROFILES="$TMP_ROOT/profiles"
TMP_PATTERNS="$TMP_ROOT/patterns"
TMP_DATA="$TMP_ROOT/data"
TMP_ZIP="$TMP_ROOT/fuzzy_macro.zip"
TMP_EXTRACT="$TMP_ROOT/extract"

# ---------- DOWNLOAD ----------

gui "Downloading Fuzzy Macro…"

curl -L -o "$TMP_ZIP" \
"https://github.com/Fuzzy-Team/Fuzzy-Macro/archive/refs/heads/main.zip"

mkdir -p "$TMP_EXTRACT"
unzip -q "$TMP_ZIP" -d "$TMP_EXTRACT"

EXTRACTED_FOLDER="$TMP_EXTRACT/Fuzzy-Macro-main"

if [[ ! -d "$EXTRACTED_FOLDER" ]]; then
    gui_ok "ERROR: Failed to extract Fuzzy Macro."
    exit 1
fi

# ---------- PRESERVE USER DATA ----------

[[ -d "$SCRIPT_DIR/settings/profiles" ]] && cp -R "$SCRIPT_DIR/settings/profiles" "$TMP_PROFILES"
[[ -d "$SCRIPT_DIR/settings/patterns" ]] && cp -R "$SCRIPT_DIR/settings/patterns" "$TMP_PATTERNS"
[[ -d "$SCRIPT_DIR/src/data" ]] && cp -R "$SCRIPT_DIR/src/data" "$TMP_DATA"

# ---------- REMOVE OLD FILES ----------

gui "Migrating files…

Your profiles will be preserved."

find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 \
    ! -name "settings" \
    ! -name "settings_backup_*" \
    -exec rm -rf {} +

cp -R "$EXTRACTED_FOLDER"/* "$SCRIPT_DIR/"

# ---------- RESTORE DATA ----------

[[ -d "$TMP_PROFILES" ]] && mkdir -p "$SCRIPT_DIR/settings" && cp -R "$TMP_PROFILES" "$SCRIPT_DIR/settings/"
[[ -d "$TMP_DATA/data" ]] && mkdir -p "$SCRIPT_DIR/src" && cp -R "$TMP_DATA/data" "$SCRIPT_DIR/src/"

if [[ -d "$TMP_PATTERNS" ]]; then
    mkdir -p "$SCRIPT_DIR/settings/patterns"
    TS=$(date +%Y%m%d_%H%M%S)
    for item in "$TMP_PATTERNS"/*; do
        name=$(basename "$item")
        dest="$SCRIPT_DIR/settings/patterns/$name"
        [[ -e "$dest" ]] && dest="$dest.from_existance_$TS"
        cp -R "$item" "$dest"
    done
fi

# ---------- RESTORE SCRIPT ----------

# If we have a local copy of the migration script (downloaded when run remotely),
# save it into the target folder as migrate_from_existance.command so the user keeps
# a copy of the migration helper.
if [[ -f "$MIGRATION_SCRIPT" ]]; then
    cp "$MIGRATION_SCRIPT" "$SCRIPT_DIR/migrate_from_existance.command"
    chmod +x "$SCRIPT_DIR/migrate_from_existance.command"
fi

# ---------- PERMISSIONS ----------

find "$SCRIPT_DIR" -type f \( -name "*.command" -o -name "*.sh" \) -exec chmod +x {} +
xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true

# ---------- DEPENDENCIES ----------

if [[ -f "$SCRIPT_DIR/install_dependencies.command" ]]; then
    if gui_yes_no "Run Fuzzy Macro dependency installer now?"; then
        (cd "$SCRIPT_DIR" && bash "./install_dependencies.command")
    else
        gui_ok "Dependencies not installed. Run install_dependencies.command manually later."
    fi
fi

# ---------- CLEANUP ----------

rm -rf "$TMP_ROOT"

# ---------- BACKUP CLEANUP ----------

if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
    if gui_yes_no "Delete backup folder?

$BACKUP_DIR"; then
        rm -rf "$BACKUP_DIR"
    fi
fi


# ---------- DONE ----------

gui_ok "Migration complete ✓

Your folder is now Fuzzy Macro.

Profiles location:
$SCRIPT_DIR/settings/profiles"

exit 0
