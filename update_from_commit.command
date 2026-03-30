#!/bin/bash

# Update an existing Fuzzy Macro install from a specific commit hash.
# Mirrors src/modules/misc/update.py:update_from_commit behavior.

set -u

msg() {
    osascript -e "display dialog \"$1\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1 || true
}

err_and_exit() {
    msg "$1"
    echo "$1" >&2
    exit 1
}

# Determine installation root similarly to update.py (cwd.replace('/src', '')).
PWD_NOW="$(pwd)"
if [[ "$PWD_NOW" == */src ]]; then
    DESTINATION="${PWD_NOW%/src}"
else
    DESTINATION="$PWD_NOW"
fi

if [[ ! -d "$DESTINATION" ]]; then
    err_and_exit "Invalid install directory: $DESTINATION"
fi

COMMIT_HASH="${1:-}"
if [[ -z "$COMMIT_HASH" ]]; then
    COMMIT_HASH=$(osascript <<'APPLESCRIPT'
try
    text returned of (display dialog "Enter commit hash to install:" default answer "" buttons {"Cancel", "Update"} default button "Update")
on error
    return ""
end try
APPLESCRIPT
)
    COMMIT_HASH="${COMMIT_HASH%$'\n'}"
fi

if [[ -z "$COMMIT_HASH" ]]; then
    err_and_exit "No commit hash provided. Update aborted."
fi

PROTECTED_FOLDERS=(
    "src/data/user"
    "settings/profiles"
    "settings/patterns"
)
PROTECTED_FILES=(
    ".git"
)

BACKUP_PATH="$DESTINATION/backup_macro.zip"
MARKER_PATH="$DESTINATION/.backup_pending"
REMOTE_ZIP="https://github.com/Fuzzy-Team/Fuzzy-Macro/archive/${COMMIT_HASH}.zip"

msg "Update in progress to commit ${COMMIT_HASH}. Do not close terminal."

# Create backup excluding protected folders/files.
(
    cd "$DESTINATION" || exit 1
    rm -f "$BACKUP_PATH"

    ZIP_EXCLUDES=(
        "src/data/user/*"
        "settings/profiles/*"
        "settings/patterns/*"
        ".git"
        ".git/*"
        "backup_macro.zip"
    )

    zip -r "$BACKUP_PATH" . -x "${ZIP_EXCLUDES[@]}" >/dev/null 2>&1 || true
)

echo "1" > "$MARKER_PATH" 2>/dev/null || true

TMP_ROOT="$(mktemp -d /tmp/fuzzy_update_commit.XXXXXX)"
TMP_ZIP="$TMP_ROOT/update.zip"
TMP_EXTRACT="$TMP_ROOT/extract"
mkdir -p "$TMP_EXTRACT"

cleanup_tmp() {
    rm -rf "$TMP_ROOT" >/dev/null 2>&1 || true
}
trap cleanup_tmp EXIT

# Download zip for target commit.
if ! curl -L --fail --max-time 90 -o "$TMP_ZIP" "$REMOTE_ZIP"; then
    err_and_exit "Could not download update zip for commit ${COMMIT_HASH}."
fi

if ! unzip -q "$TMP_ZIP" -d "$TMP_EXTRACT"; then
    err_and_exit "Could not extract update zip for commit ${COMMIT_HASH}."
fi

EXTRACTED=""
for d in "$TMP_EXTRACT"/Fuzzy-Macro*; do
    if [[ -d "$d" ]]; then
        EXTRACTED="$d"
        break
    fi
done

if [[ -z "$EXTRACTED" ]]; then
    # Fallback: any extracted directory containing src.
    for d in "$TMP_EXTRACT"/*; do
        if [[ -d "$d" && -d "$d/src" ]]; then
            EXTRACTED="$d"
            break
        fi
    done
fi

if [[ -z "$EXTRACTED" ]]; then
    err_and_exit "Could not locate extracted update folder."
fi

# Merge all files except protected folders/files.
if ! rsync -a \
    --exclude "src/data/user/***" \
    --exclude "settings/profiles/***" \
    --exclude "settings/patterns/***" \
    --exclude ".git" \
    "$EXTRACTED/" "$DESTINATION/"; then
    err_and_exit "Error while applying update files."
fi

# Merge patterns without overwriting existing files.
SRC_PATTERNS="$EXTRACTED/settings/patterns"
DST_PATTERNS="$DESTINATION/settings/patterns"
if [[ -d "$SRC_PATTERNS" ]]; then
    while IFS= read -r -d '' src_file; do
        rel_path="${src_file#$SRC_PATTERNS/}"
        dest_file="$DST_PATTERNS/$rel_path"
        dest_dir="$(dirname "$dest_file")"
        mkdir -p "$dest_dir"

        if [[ ! -f "$dest_file" ]]; then
            cp -f "$src_file" "$dest_file" >/dev/null 2>&1 || true
        else
            base_name="$(basename "$dest_file")"
            name="${base_name%.*}"
            ext=""
            if [[ "$base_name" == *.* ]]; then
                ext=".${base_name##*.}"
            fi
            if [[ "$name" == "$base_name" ]]; then
                ext=""
            fi
            i=1
            while true; do
                new_name="${name}.new${i}${ext}"
                new_path="$dest_dir/$new_name"
                if [[ ! -e "$new_path" ]]; then
                    cp -f "$src_file" "$new_path" >/dev/null 2>&1 || true
                    break
                fi
                i=$((i + 1))
            done
        fi
    done < <(find "$SRC_PATTERNS" -type f -print0)

    # Cleanup .newN duplicates similarly to update.py.
    while IFS= read -r -d '' candidate; do
        fname="$(basename "$candidate")"
        dirn="$(dirname "$candidate")"
        if [[ "$fname" =~ ^(.+)\.new[0-9]+(\..+)?$ ]]; then
            base_part="${BASH_REMATCH[1]}"
            ext_part="${BASH_REMATCH[2]:-}"
            target="$dirn/${base_part}${ext_part}"
            if [[ -e "$target" ]]; then
                rm -f "$candidate" >/dev/null 2>&1 || true
            else
                mv -f "$candidate" "$target" >/dev/null 2>&1 || true
            fi
        fi
    done < <(find "$DST_PATTERNS" -type f -name "*.new*" -print0)
fi

# Ensure run script is executable.
RUN_MACRO="$DESTINATION/run_macro.command"
if [[ -f "$RUN_MACRO" ]]; then
    chmod +x "$RUN_MACRO" >/dev/null 2>&1 || true
fi

# Write commit marker so UI can show commit hash.
COMMIT_MARKER="$DESTINATION/src/webapp/updated_commit.txt"
mkdir -p "$(dirname "$COMMIT_MARKER")" >/dev/null 2>&1 || true
printf '%s' "${COMMIT_HASH:0:7}" > "$COMMIT_MARKER" 2>/dev/null || true

# Attempt to run dependency installer in detached mode.
INSTALL_SCRIPT="$DESTINATION/install_dependencies.command"
if [[ -f "$INSTALL_SCRIPT" ]]; then
    chmod +x "$INSTALL_SCRIPT" >/dev/null 2>&1 || true
    nohup sh "$INSTALL_SCRIPT" >/dev/null 2>&1 < /dev/null &
fi

msg "Update complete. You can now relaunch the macro."
echo "Update success: commit ${COMMIT_HASH}"
exit 0
