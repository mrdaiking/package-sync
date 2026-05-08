#!/usr/bin/env bash
# Bootstrap installer — curl https://raw.githubusercontent.com/.../install.sh | bash

set -euo pipefail

REPO="https://github.com/mrdaiking/package-sync"  # update when published
INSTALL_DIR="$HOME/.package-sync"
BIN_DIR="$HOME/.local/bin"

echo "package-sync installer"
echo ""

# Dependencies check
for dep in jq git; do
  if ! command -v "$dep" &>/dev/null; then
    echo "Missing: $dep"
    if command -v brew &>/dev/null; then
      echo "Installing $dep via brew..."
      brew install "$dep"
    else
      echo "Install $dep manually then re-run."
      exit 1
    fi
  fi
done

# Clone or update
if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Updating existing installation..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "Installing to $INSTALL_DIR ..."
  git clone "$REPO" "$INSTALL_DIR"
fi

# Make scripts executable
chmod +x "$INSTALL_DIR/package-sync.sh"
chmod +x "$INSTALL_DIR/hooks/shell.sh"
chmod +x "$INSTALL_DIR/sync/gist.sh"
mkdir -p "$INSTALL_DIR/hooks" "$INSTALL_DIR/bin"
cp "$INSTALL_DIR/hooks/shell.sh" "$INSTALL_DIR/hooks/shell.sh"

# Symlink binary
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/package-sync.sh" "$BIN_DIR/package-sync"

# Add bin to PATH if missing
shell_rc=""
case "$SHELL" in
  */zsh)  shell_rc="$HOME/.zshrc" ;;
  */bash) shell_rc="$HOME/.bashrc" ;;
esac

if [[ -n "$shell_rc" ]]; then
  if ! grep -q "$BIN_DIR" "$shell_rc" 2>/dev/null; then
    echo "" >> "$shell_rc"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$shell_rc"
  fi
fi

echo ""
echo "Installed. Run setup:"
echo "  package-sync init      # add shell hooks"
echo "  package-sync sync setup  # link GitHub Gist for cross-device sync"
echo ""
echo "Restart terminal or: source $shell_rc"
