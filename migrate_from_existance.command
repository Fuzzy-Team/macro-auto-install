#!/bin/bash

# -------------------------------
# Existance to Fuzzy Macro Migration Script
# macOS 10.12+ / Intel or Apple Silicon (M1–M4)
# Note: This script is untested and is not advised at this current time.
# -------------------------------

# GUI helper
gui() {
    osascript -e "display dialog \"$1\" buttons {\"Continue\"} default button \"Continue\""
}

gui_yes_no() {
    result=$(osascript -e "display dialog \"$1\" buttons {\"Yes\", \"No\"} default button \"Yes\"" 2>&1)
    if echo "$result" | grep -q "Yes"; then
        return 0
    else
        return 1
    fi
}

gui_ok() {
    osascript -e "display dialog \"$1\" buttons {\"OK\"} default button \"OK\""
}

# --- WELCOME ---
gui "Welcome to the Existance → Fuzzy Macro Migration Tool.\n\nThis script will help you migrate your settings from Existance Macro to Fuzzy Macro.\n\nClick Continue to begin."

# --- ASK ABOUT UNINSTALLING EXISTANCE ---
if gui_yes_no "Do you want to uninstall the Existance Macro virtual environment?\n\nThis will delete the 'bss-macro-env' folder.\n\n(Your profiles will be preserved)"; then
    gui "Removing Existance Macro virtual environment..."
    rm -rf "$HOME/bss-macro-env"
    gui "Existance virtual environment removed."
else
    gui "Keeping Existance virtual environment intact."
fi

# --- CHECK IF SCRIPT IS IN EXISTANCE FOLDER ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Look for indicators that this is the Existance Macro folder
# (Check for common files/folders that would be in Existance Macro)
if [[ ! -d "$SCRIPT_DIR/settings" ]]; then
    gui_ok "ERROR: This script must be placed in your Existance Macro folder.\n\nPlease move this file into your Existance Macro directory and run it again."
    exit 1
fi

if gui_yes_no "Is this file currently in your Existance Macro folder?\n\nCurrent location:\n$SCRIPT_DIR"; then
    gui "Great!  Continuing with migration..."
else
    gui_ok "Please move this file into your Existance Macro folder and run it again."
    exit 1
fi

# --- BACKUP PROFILES ---
gui "Backing up your profiles..."

BACKUP_DIR="$SCRIPT_DIR/settings_backup_$(date +%Y%m%d_%H%M%S)"
if [[ -d "$SCRIPT_DIR/settings/profiles" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp -R "$SCRIPT_DIR/settings/profiles" "$BACKUP_DIR/"
    gui "Profiles backed up to:\n$BACKUP_DIR"
else
    gui "No profiles folder found. Skipping backup."
    BACKUP_DIR=""
fi

# --- DOWNLOAD FUZZY MACRO ---
gui "Downloading Fuzzy Macro from GitHub..."

TMP_ZIP="/tmp/fuzzy_macro_migration.zip"
curl -L -o "$TMP_ZIP" "https://github.com/Fuzzy-Team/Fuzzy-Macro/archive/refs/heads/main.zip"

if [[ ! -f "$TMP_ZIP" ]]; then
    gui_ok "ERROR: Failed to download Fuzzy Macro.\n\nPlease check your internet connection and try again."
    exit 1
fi

# --- EXTRACT TO TEMPORARY LOCATION ---
gui "Extracting Fuzzy Macro files..."

TMP_EXTRACT="/tmp/fuzzy_macro_extract"
rm -rf "$TMP_EXTRACT"
mkdir -p "$TMP_EXTRACT"
unzip -o "$TMP_ZIP" -d "$TMP_EXTRACT"
rm "$TMP_ZIP"

# Find the extracted folder (should be Fuzzy-Macro-main)
EXTRACTED_FOLDER=$(find "$TMP_EXTRACT" -maxdepth 1 -type d -name "Fuzzy-Macro-main" | head -n 1)

if [[ -z "$EXTRACTED_FOLDER" ]]; then
    gui_ok "ERROR: Could not find extracted Fuzzy Macro folder."
    exit 1
fi

# --- REPLACE FILES (PRESERVE SETTINGS AND MIGRATION SCRIPT) ---
gui "Migrating files to Fuzzy Macro.. .\n\nYour profiles will be preserved."

# Save this migration script temporarily
MIGRATION_SCRIPT="$SCRIPT_DIR/migrate_from_existance.command"
TMP_MIGRATION="/tmp/migrate_from_existance_temp.command"
cp "$MIGRATION_SCRIPT" "$TMP_MIGRATION"

# Save profiles temporarily
TMP_PROFILES="/tmp/profiles_temp"
rm -rf "$TMP_PROFILES"
if [[ -d "$SCRIPT_DIR/settings/profiles" ]]; then
    cp -R "$SCRIPT_DIR/settings/profiles" "$TMP_PROFILES"
fi

# Delete all files except settings folder
find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 !  -name "settings" ! -name "settings_backup_*" -exec rm -rf {} +

# Copy all Fuzzy Macro files
cp -R "$EXTRACTED_FOLDER"/* "$SCRIPT_DIR/"

# Restore profiles
if [[ -d "$TMP_PROFILES" ]]; then
    mkdir -p "$SCRIPT_DIR/settings"
    cp -R "$TMP_PROFILES" "$SCRIPT_DIR/settings/"
    rm -rf "$TMP_PROFILES"
    gui "Your profiles have been restored."
fi

# Restore migration script
cp "$TMP_MIGRATION" "$SCRIPT_DIR/migrate_from_existance.command"
chmod +x "$SCRIPT_DIR/migrate_from_existance.command"
rm "$TMP_MIGRATION"

# Cleanup
rm -rf "$TMP_EXTRACT"

# Remove quarantine attributes
xattr -dr com.apple.quarantine "$SCRIPT_DIR"
chmod -R +x "$SCRIPT_DIR"

# --- RUN INSTALL DEPENDENCIES ---
gui "Running Fuzzy Macro dependency installation..."

if [[ -f "$SCRIPT_DIR/install_dependencies.command" ]]; then
    chmod +x "$SCRIPT_DIR/install_dependencies.command"
    cd "$SCRIPT_DIR"
    bash "$SCRIPT_DIR/install_dependencies.command"
else
    gui_ok "WARNING: install_dependencies.command not found.\n\nPlease run it manually from the Fuzzy Macro folder."
fi

# --- CLEANUP OPTIONS ---
# Ask about deleting backup
if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]]; then
    if gui_yes_no "Migration complete! ✓\n\nDo you want to delete the backup folder?\n\n$BACKUP_DIR\n\n(Your profiles are already restored in the settings folder)"; then
        rm -rf "$BACKUP_DIR"
        gui "Backup folder deleted."
    else
        gui "Backup folder kept at:\n$BACKUP_DIR"
    fi
fi

# Ask about deleting migration script
if gui_yes_no "Do you want to delete this migration script?\n\n$MIGRATION_SCRIPT\n\n(You won't need it anymore since migration is complete)"; then
    # Use a separate script to delete this file after it exits
    CLEANUP_SCRIPT="/tmp/cleanup_migration. sh"
    cat > "$CLEANUP_SCRIPT" <<EOF
#!/bin/bash
sleep 1
rm -f "$MIGRATION_SCRIPT"
rm -f "$CLEANUP_SCRIPT"
EOF
    chmod +x "$CLEANUP_SCRIPT"
    nohup "$CLEANUP_SCRIPT" &>/dev/null &
    gui "Migration script will be deleted shortly."
else
    gui "Migration script kept at:\n$MIGRATION_SCRIPT"
fi

# --- COMPLETION ---
FINAL_MSG="Migration complete!  ✓\n\nYour Existance Macro folder has been converted to Fuzzy Macro.\n\nYour profiles are preserved in:\n$SCRIPT_DIR/settings/profiles"

if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]]; then
    FINAL_MSG="$FINAL_MSG\n\nBackup location:\n$BACKUP_DIR"
fi

FINAL_MSG="$FINAL_MSG\n\nYou can now run Fuzzy Macro!"

gui_ok "$FINAL_MSG"

exit 0
