#!/bin/sh
set -eu

INSTALL_DIR="$HOME/.local/bin"

case "$(uname -m)" in
  x86_64|amd64)   ARCH="x86_64" ;;
  aarch64|arm64)  ARCH="aarch64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

ARCHIVE_NAME="zerotty-${ARCH}-linux-release.tar.gz"
API="https://codeberg.org/api/v1/repos/panda2code/zerotty/releases?limit=1"

# /releases/latest ignores pre-releases, so take the newest entry from the list
RELEASE=$(curl -fsSL "$API")

URL=$(printf '%s' "$RELEASE" | jq -r --arg n "$ARCHIVE_NAME" \
  '.[0].assets[] | select(.name == $n) | .browser_download_url')
SUMS_URL=$(printf '%s' "$RELEASE" | jq -r \
  '.[0].assets[] | select(.name == "sha256sum.txt") | .browser_download_url')

if [ -z "$URL" ]; then
  echo "Asset '$ARCHIVE_NAME' not found in the newest release. Available assets:" >&2
  printf '%s' "$RELEASE" | jq -r '.[0].assets[].name' >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $ARCHIVE_NAME ..."
curl -fL "$URL" -o "$TMP/$ARCHIVE_NAME"

if [ -n "$SUMS_URL" ]; then
  curl -fsSL "$SUMS_URL" -o "$TMP/sha256sum.txt"
  EXPECTED=$(grep -F "$ARCHIVE_NAME" "$TMP/sha256sum.txt" | awk '{print $1}' | head -n1)
  ACTUAL=$(sha256sum "$TMP/$ARCHIVE_NAME" | awk '{print $1}')
  if [ -n "$EXPECTED" ] && [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Checksum mismatch, aborting." >&2
    exit 1
  fi
fi

mkdir -p "$TMP/extract" "$INSTALL_DIR"
tar -xzf "$TMP/$ARCHIVE_NAME" -C "$TMP/extract"

# Works whether the binary is at the archive root or inside a folder
BIN=$(find "$TMP/extract" -type f -name zerotty | head -n1)
if [ -z "$BIN" ]; then
  echo "No 'zerotty' binary found in the archive." >&2
  exit 1
fi

install -m 755 "$BIN" "$INSTALL_DIR/zerotty"
echo "Installed to $INSTALL_DIR/zerotty"

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "Note: $INSTALL_DIR is not in your PATH." ;;
esac
