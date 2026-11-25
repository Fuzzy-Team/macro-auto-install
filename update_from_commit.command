#!/bin/bash

# Update (or roll back) an existing Fuzzy Macro install to a specific commit or tester ID.
#
#   update_from_commit.command [commit-hash]
#
# Your profiles, patterns, user data and AI models are left alone.

set -u

msg() {
    osascript -e "display dialog \"$1\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1 || true
}

err_and_exit() {
    msg "$1"
    echo "$1" >&2
    exit 1
}

# Opens on the default install folder when it exists. Prints nothing if cancelled.
choose_folder() {
    local default="$HOME/Downloads/Fuzzy Macro"
    [[ -d "$default" ]] || default="$HOME/Downloads"
    osascript - "$default" <<'APPLESCRIPT' 2>/dev/null
on run argv
    tell application "Finder"
        activate
        set theFolder to choose folder with prompt "Select your Fuzzy Macro folder to update." default location (POSIX file (item 1 of argv) as alias)
        return POSIX path of theFolder
    end tell
end run
APPLESCRIPT
}

PICKED="$(choose_folder)"
DESTINATION="${PICKED%$'\n'}"
DESTINATION="${DESTINATION%/}"
[[ -n "$DESTINATION" ]] || err_and_exit "No folder chosen. Update cancelled."

# Refuse anything that is not a Fuzzy Macro folder, since files are copied into it.
if [[ ! -f "$DESTINATION/run_macro.command" || ! -d "$DESTINATION/src" ]]; then
    err_and_exit "This does not look like a Fuzzy Macro folder: $DESTINATION"
fi

COMMIT_HASH="${1:-}"
if [[ -z "$COMMIT_HASH" ]]; then
    COMMIT_HASH=$(osascript <<'APPLESCRIPT' 2>/dev/null
try
    text returned of (display dialog "Enter the commit hash or tester ID to install:" default answer "" buttons {"Cancel", "Update"} default button "Update")
on error
    return ""
end try
APPLESCRIPT
)
fi

# Keep only the first hash-looking token.
COMMIT_HASH="$(printf '%s' "$COMMIT_HASH" | grep -Eo '[0-9a-fA-F]{7,40}' | head -n1)"
[[ -n "$COMMIT_HASH" ]] || err_and_exit "No commit hash provided. Update cancelled."

TMP_ROOT="$(mktemp -d /tmp/fuzzy_update_commit.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT
TMP_ZIP="$TMP_ROOT/update.zip"
TMP_EXTRACT="$TMP_ROOT/extract"

# Download first, so a failed download leaves the install untouched.
echo "Downloading ${COMMIT_HASH}..."
curl -fL --retry 3 --connect-timeout 20 --max-time 600 -# -o "$TMP_ZIP" \
    "https://github.com/Fuzzy-Team/Fuzzy-Macro/archive/${COMMIT_HASH}.zip" ||
    err_and_exit "Could not download commit ${COMMIT_HASH}. Check the hash and your internet connection."
unzip -q "$TMP_ZIP" -d "$TMP_EXTRACT" || err_and_exit "Could not unzip commit ${COMMIT_HASH}."

# The zip holds one folder (Fuzzy-Macro-<hash>).
EXTRACTED="$(find "$TMP_EXTRACT" -mindepth 1 -maxdepth 1 -type d | head -n1)"
[[ -d "$EXTRACTED/src" ]] || err_and_exit "Commit ${COMMIT_HASH} does not contain a Fuzzy Macro."

# Back up the code. Your data is not included, and neither are the AI models and recordings, which are huge.
# The macro deletes this backup after one full launch.
BACKUP_PATH="$DESTINATION/backup_macro.zip"
echo "Backing up the current version..."
rm -f "$BACKUP_PATH"
if (cd "$DESTINATION" && zip -rq "$BACKUP_PATH" . \
        -x "src/data/user/*" "src/data/models/*" "settings/profiles/*" "settings/patterns/*" \
        ".git" ".git/*" "backup_macro.zip"); then
    echo "1" > "$DESTINATION/.backup_pending"
else
    rm -f "$BACKUP_PATH"
    echo "Backup failed. Continuing without one." >&2
fi

# Copy the new version over the install. Protected folders are left as they are.
echo "Applying update..."
rsync -a \
    --exclude "src/data/user/***" \
    --exclude "src/data/models/***" \
    --exclude "settings/profiles/***" \
    --exclude "settings/patterns/***" \
    --exclude ".git" \
    "$EXTRACTED/" "$DESTINATION/" || err_and_exit "Error while applying the update files."

# Patterns: keep yours and add the built-in ones you don't have yet.
if [[ -d "$EXTRACTED/settings/patterns" ]]; then
    mkdir -p "$DESTINATION/settings/patterns"
    rsync -a --ignore-existing "$EXTRACTED/settings/patterns/" "$DESTINATION/settings/patterns/"
fi

find "$DESTINATION" -type f \( -name "*.command" -o -name "*.sh" -o -name "*.so" -o -name "*.dylib" \) -exec chmod +x {} + 2>/dev/null

# The macro shows this commit in its settings.
mkdir -p "$DESTINATION/src/webapp"
printf '%s' "${COMMIT_HASH:0:7}" > "$DESTINATION/src/webapp/updated_commit.txt"

# The libraries can differ between versions.
if [[ -f "$DESTINATION/install_dependencies.command" ]]; then
    echo "Updating libraries..."
    (cd "$DESTINATION" && bash "./install_dependencies.command") ||
        err_and_exit "The code was updated, but installing the libraries failed. Scroll up in Terminal to see the error, then run install_dependencies.command in your Fuzzy Macro folder."
fi

msg "Update complete. You can now relaunch the macro."
echo "Update success: commit ${COMMIT_HASH}"
exit 0
