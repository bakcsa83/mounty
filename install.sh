#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"

echo "Mounty - Install"
echo "---"

# Ensure ~/.local/bin exists and is in PATH
mkdir -p "$INSTALL_DIR"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "warning: $INSTALL_DIR is not in your PATH"
    echo "Add this to your ~/.bashrc or ~/.zshrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# Install cifs-utils if missing
if ! command -v mount.cifs &>/dev/null; then
    echo "Installing cifs-utils..."
    sudo apt install -y cifs-utils
else
    echo "cifs-utils is already installed"
fi

# Copy script
cp "$SCRIPT_DIR/mounty" "$INSTALL_DIR/mounty"
chmod +x "$INSTALL_DIR/mounty"
echo "Installed mounty to $INSTALL_DIR/mounty"

# Create directories
mkdir -p "$HOME/.mounty"
mkdir -p "$HOME/mnt"
echo "Created ~/.mounty and ~/mnt directories"

echo "---"
echo "Done. Run 'mounty help' to get started."
