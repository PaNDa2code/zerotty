#!/bin/sh

set -eu

ZIG_VERSION="${1:-0.17.0}"
HOST_ARCH=$(arch)
HOST_OS="linux"

INSTALL_DIR="/usr/local/zig"

ZIG_ARCHIVE="zig-$HOST_ARCH-$HOST_OS-$ZIG_VERSION.tar.xz"

MIRRORS=$(curl -sSf https://ziglang.org/download/community-mirrors.txt | shuf)
PUBKEY='RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U'

downloaded=false

for MIRROR in $MIRRORS
do
  ZIG_URL="$MIRROR/$ZIG_ARCHIVE"
  echo "Downloading $ZIG_URL"

  if curl -s -fL --retry 2 -o "$ZIG_ARCHIVE.minisig" "$ZIG_URL.minisig" &&
    curl -s -fL --retry 2 -o "$ZIG_ARCHIVE" "$ZIG_URL" &&
    xz -t "$ZIG_ARCHIVE" &&
    minisign -Vm "$ZIG_ARCHIVE" -P "$PUBKEY"; then
    downloaded=true
    break
  fi

  echo "Mirror failed or signature invalid, trying next" >&2
done

if [ "$downloaded" != true ]; then
  echo "Failed to download a valid Zig archive" >&2
  exit 1
fi

echo "Downloaded $ZIG_ARCHIVE"

ZIG_DIR=$(basename $ZIG_ARCHIVE .tar.xz)

tar -xf "$ZIG_ARCHIVE"

sudo rm -rf "$INSTALL_DIR"
sudo mv "$ZIG_DIR" "$INSTALL_DIR"

sudo ln -sf "$INSTALL_DIR/zig" /usr/local/bin/zig

echo "Installed zig $(zig version) successfully"
