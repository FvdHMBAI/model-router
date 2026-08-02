#!/bin/bash
# install.sh — Install model-router to your system
set -euo pipefail

INSTALL_DIR="${1:-/usr/local/bin}"
CONFIG_DIR="${MODEL_ROUTER_CONFIG_DIR:-$HOME/.config/model-router}"

echo "Installing model-router..."
echo "  Script:  $INSTALL_DIR/model-router"
echo "  Config:  $CONFIG_DIR/model-routing.json"

mkdir -p "$CONFIG_DIR"

cp model-router.sh "$INSTALL_DIR/model-router"
chmod +x "$INSTALL_DIR/model-router"

if [ ! -f "$CONFIG_DIR/model-routing.json" ]; then
  cp model-routing.json "$CONFIG_DIR/model-routing.json"
  echo "  Config copied (edit to match your setup)"
else
  echo "  Config already exists, skipping (check model-routing.json for new options)"
fi

# Point the script at the config
export MODEL_ROUTER_CONFIG="$CONFIG_DIR/model-routing.json"

echo ""
echo "Done. Usage:"
echo "  eval \$(model-router standard)"
echo "  echo \$MODEL_ID  # -> claude-sonnet-5"
echo ""
echo "Add to your .bashrc / .zshrc:"
echo "  export MODEL_ROUTER_CONFIG=\"$CONFIG_DIR/model-routing.json\""
