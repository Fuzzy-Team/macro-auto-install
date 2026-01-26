#!/bin/bash

# ---------------------------------------------
# Existance → Fuzzy Macro Migration Script
# macOS 10.12+ / Intel or Apple Silicon
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
    local msg="$1"
    # Escape double quotes for AppleScript
    local esc_msg
    esc_msg=$(printf '%s' "$msg" | sed 's/"/\\"/g')
    local ans
    ans=$(osascript <<APPLESCRIPT
try
    display dialog "${esc_msg}" buttons {"Yes", "No"} default button "Yes"
    if button returned of result is "Yes" then
        return "YES"
    else
        return "NO"
    end if
on error
    return "NO"
end try
APPLESCRIPT
)

    # Trim trailing newline
    ans=${ans%$'\n'}

    if [[ "$ans" == "YES" ]]; then
        return 0
    else
        return 1
    fi
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

# Prompt user to select the macro folder so the script can be run remotely.
# This brings Finder to the front and will not return until a folder is chosen.
choose_folder() {
    while true; do
        CHOSEN=$(osascript <<'APPLESCRIPT'
tell application "Finder"
    activate
    try
        set theFolder to choose folder with prompt "Select your Existance Macro folder to migrate."
        POSIX path of theFolder
    on error
        return ""
    end try
end tell
APPLESCRIPT
)

        # Trim trailing newline
        CHOSEN=${CHOSEN%$'\n'}

        if [[ -n "$CHOSEN" ]]; then
            echo "$CHOSEN"
            return 0
        fi

        # If user cancelled, politely remind them and loop again.
        osascript <<EOF >/dev/null
display dialog "Please select a folder in Finder to continue the migration." buttons {"OK"} default button "OK"
EOF
    done
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

while true; do
    if gui_yes_no "Confirm script location:

$SCRIPT_DIR

Is this your Existance Macro folder?"; then
        break
    else
        gui "Let's choose the folder again."
        if CHOSEN_DIR=$(choose_folder 2>/dev/null); then
            SCRIPT_DIR="${CHOSEN_DIR%/}"
            # loop back to confirm the newly chosen folder
            continue
        else
            gui_ok "No folder selected. Aborting."
            exit 1
        fi
    fi
done

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

gui "Migrating files…

Your profiles will be preserved."

# ---------- PROTECTED PATHS ----------
# These match update.py's protected logic
PROTECTED_FOLDERS=(
    "settings/profiles"
    "settings/patterns"
    "src/data/user"
)
PROTECTED_FILES=(
    ".git"
)


# Helper: check if a path is protected
is_protected() {
    local relpath="$1"
    for pf in "${PROTECTED_FOLDERS[@]}"; do
        [[ "$relpath" == "$pf" || "$relpath" == "$pf"/* ]] && return 0
    done
    for pf in "${PROTECTED_FILES[@]}"; do
        [[ "$relpath" == "$pf" ]] && return 0
    done
    return 1
}

# Helper: safe rm -rf (refuse to remove /, empty, or protected)
safe_rm_rf() {
    local target="$1"
    # Refuse to remove empty or root
    [[ -z "$target" || "$target" == "/" ]] && {
        echo "[ERROR] Refusing to rm -rf empty or root path! ($target)" >&2
        return 1
    }
    # Refuse to remove protected
    local relname=$(basename "$target")
    is_protected "$relname" && {
        echo "[INFO] Skipping protected path: $target" >&2
        return 0
    }
    rm -rf "$target"
}

# ---------- REMOVE OLD FILES (EXCEPT PROTECTED) ----------
gui "Migrating files…

Your profiles, patterns, and user data will be preserved."


shopt -s dotglob
for item in "$SCRIPT_DIR"/*; do
    name=$(basename "$item")
    # skip protected folders/files and backups
    is_protected "$name" && continue
    [[ "$name" == "settings_backup_"* ]] && continue
    safe_rm_rf "$item"
done
shopt -u dotglob

# ---------- COPY NEW FILES (EXCEPT PROTECTED) ----------
copy_dir_except_protected() {
    local src="$1"
    local dst="$2"
    local relbase="$3"
    mkdir -p "$dst"
    shopt -s dotglob
    for item in "$src"/*; do
        local name=$(basename "$item")
        local relpath="$relbase$name"
        is_protected "$relpath" && continue
        if [[ -d "$item" ]]; then
            copy_dir_except_protected "$item" "$dst/$name" "$relpath/"
        else
            cp -p "$item" "$dst/$name"
        fi
    done
    shopt -u dotglob
}

copy_dir_except_protected "$EXTRACTED_FOLDER" "$SCRIPT_DIR" ""

# ---------- RESTORE DATA ----------
[[ -d "$TMP_PROFILES" ]] && mkdir -p "$SCRIPT_DIR/settings" && cp -R "$TMP_PROFILES" "$SCRIPT_DIR/settings/"
[[ -d "$TMP_DATA/data" ]] && mkdir -p "$SCRIPT_DIR/src/data" && cp -R "$TMP_DATA/data" "$SCRIPT_DIR/src/"

# Merge patterns: if file exists, save as .newN (like update.py)
if [[ -d "$TMP_PATTERNS" ]]; then
    mkdir -p "$SCRIPT_DIR/settings/patterns"
    for item in "$TMP_PATTERNS"/*; do
        name=$(basename "$item")
        dest="$SCRIPT_DIR/settings/patterns/$name"
        if [[ ! -e "$dest" ]]; then
            cp -R "$item" "$dest"
        else
            # Find next available .newN suffix
            base="${name%.*}"
            ext="${name##*.}"
            [[ "$base" == "$ext" ]] && ext="" || ext=".$ext"
            n=1
            while [[ -e "$SCRIPT_DIR/settings/patterns/${base}.new${n}${ext}" ]]; do
                ((n++))
            done
            cp -R "$item" "$SCRIPT_DIR/settings/patterns/${base}.new${n}${ext}"
        fi
    done
    # Post-merge cleanup: promote .newN if base missing, else delete .newN
    for f in "$SCRIPT_DIR/settings/patterns"/*.new*; do
        [[ ! -e "$f" ]] && continue
        # Extract base and ext
        fname=$(basename "$f")
        if [[ "$fname" =~ ^(.+?)\.new[0-9]+(\..+)?$ ]]; then
            base="${BASH_REMATCH[1]}"
            ext="${BASH_REMATCH[2]}"
            [[ -z "$ext" ]] && ext=""
            candidate="$SCRIPT_DIR/settings/patterns/${base}${ext}"
            if [[ -e "$candidate" ]]; then
                rm -f "$f"
            else
                mv "$f" "$candidate"
            fi
        fi
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
