#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Fuzzy-Team/Fuzzy-Macro.git"
INSTALL_DIR="$HOME/Fuzzy-Macro"
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="$INSTALL_DIR/fuzzy-macro-env"

echo "==> Installing Fuzzy Macro for Linux"

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required but was not found. Install git, then run this script again."
  exit 1
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Error: python3 is required but was not found. Install Python 3, then run this script again."
  exit 1
fi

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "==> Updating existing Fuzzy Macro checkout"
  git -C "$INSTALL_DIR" pull --ff-only
else
  if [ -e "$INSTALL_DIR" ]; then
    echo "Error: $INSTALL_DIR already exists but is not a git repository."
    echo "Move or remove it, then run this script again."
    exit 1
  fi

  echo "==> Cloning Fuzzy Macro"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

echo "==> Creating virtual environment"
"$PYTHON_BIN" -m venv "$VENV_DIR"

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

echo "==> Upgrading pip"
python -m pip install --upgrade pip setuptools wheel

if [ -f requirements.txt ]; then
  echo "==> Installing Python requirements"
  python -m pip install -r requirements.txt
elif [ -f src/requirements.txt ]; then
  echo "==> Installing Python requirements"
  python -m pip install -r src/requirements.txt
else
  echo "Warning: No requirements.txt file found. Skipping dependency install."
fi

if [ -f install_dependencies.sh ]; then
  echo "==> Running Linux dependency script from Fuzzy Macro"
  chmod +x install_dependencies.sh
  ./install_dependencies.sh
elif [ -f install_dependencies.command ]; then
  echo "==> Running dependency script from Fuzzy Macro"
  chmod +x install_dependencies.command
  ./install_dependencies.command
else
  echo "Warning: No dependency install script found in Fuzzy Macro."
fi

cat <<EOF

Fuzzy Macro has been installed at:
$INSTALL_DIR

To run it later:
cd "$INSTALL_DIR"
source "$VENV_DIR/bin/activate"
python main.py
EOF
