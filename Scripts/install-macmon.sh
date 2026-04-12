#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer supports macOS only."
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "macmon targets Apple Silicon (arm64). Current arch: $(uname -m)"
  exit 1
fi

USER_INSTALL_DIR="${HOME}/.local/bin"
USER_INSTALL_PATH="${USER_INSTALL_DIR}/macmon"

if [[ -x "${USER_INSTALL_PATH}" ]]; then
  echo "macmon already installed: ${USER_INSTALL_PATH}"
  "${USER_INSTALL_PATH}" --version || true
  exit 0
fi

if command -v brew >/dev/null 2>&1; then
  echo "Installing macmon via Homebrew..."
  brew install macmon
  macmon --version
  exit 0
fi

if command -v port >/dev/null 2>&1; then
  echo "Installing macmon via MacPorts..."
  sudo port install macmon
  macmon --version
  exit 0
fi

echo "No package manager found. Falling back to GitHub release download..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

API_URL="https://api.github.com/repos/vladkens/macmon/releases/latest"
ASSET_URL="$(curl -fsSL "$API_URL" \
  | awk -F'"' '/browser_download_url/ {print $4}' \
  | grep -Ei 'macmon' \
  | grep -Ei 'tar.gz|zip' \
  | head -n 1)"

if [[ -z "${ASSET_URL}" ]]; then
  echo "Failed to find macOS arm64 release asset from: $API_URL"
  exit 1
fi

echo "Downloading: $ASSET_URL"
ARCHIVE_PATH="$TMP_DIR/macmon-archive"
curl -fL "$ASSET_URL" -o "$ARCHIVE_PATH"

EXTRACT_DIR="$TMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"

if [[ "$ASSET_URL" == *.zip ]]; then
  ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_DIR"
else
  tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"
fi

BIN_PATH="$(find "$EXTRACT_DIR" -type f -name macmon | head -n 1)"
if [[ -z "${BIN_PATH}" ]]; then
  echo "Downloaded release does not contain a macmon binary."
  exit 1
fi

mkdir -p "$USER_INSTALL_DIR"
echo "Installing macmon to ${USER_INSTALL_PATH}"
install -m 755 "$BIN_PATH" "$USER_INSTALL_PATH"

echo "macmon installed successfully."
"$USER_INSTALL_PATH" --version
