#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Fuzzy-Team/Fuzzy-Macro.git}"
BRANCH="${BRANCH:-linux}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Fuzzy-Macro}"

echo "==> Installing Fuzzy Macro for Linux (branch: $BRANCH)"

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required but was not found. Install git, then run this script again."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required but was not found. Install Python 3.9 (recommended), then run this script again."
  exit 1
fi

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "==> Updating existing Fuzzy Macro checkout"
  git -C "$INSTALL_DIR" fetch origin "$BRANCH"
  git -C "$INSTALL_DIR" checkout "$BRANCH"
  git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
else
  if [ -e "$INSTALL_DIR" ]; then
    echo "Error: $INSTALL_DIR already exists but is not a git repository."
    echo "Move or remove it, then run this script again."
    exit 1
  fi

  echo "==> Cloning Fuzzy Macro ($BRANCH)"
  git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

if [ ! -f install_dependencies.sh ]; then
  echo "Error: install_dependencies.sh was not found in $INSTALL_DIR"
  echo "Make sure the $BRANCH branch contains the Linux installer scripts."
  exit 1
fi

echo "==> Running Linux dependency installer"
chmod +x install_dependencies.sh run_macro.sh 2>/dev/null || true
./install_dependencies.sh

cat <<EOF

Fuzzy Macro has been installed at:
$INSTALL_DIR

Branch: $BRANCH

To run it later:
cd "$INSTALL_DIR"
./run_macro.sh

Recommended system packages:
  Debian/Ubuntu: sudo apt install xdotool wmctrl build-essential
  Fedora:        sudo dnf install xdotool wmctrl gcc gcc-c++ make
  Arch:          sudo pacman -S xdotool wmctrl base-devel

Prefer an X11 session (or XWayland). Use Sober for Roblox on Linux.
EOF
