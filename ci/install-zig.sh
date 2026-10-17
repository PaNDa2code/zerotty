#!/bin/sh

set -eu

ZIG_VERSION="${1:-0.17.0}"
HOST_ARCH=$(arch)
HOST_OS="linux"

INSTALL_DIR="/usr/local/zig"

ZIG_ARCHIVE="zig-$HOST_ARCH-$HOST_OS-$ZIG_VERSION.tar.xz"

MIRRORS=$(curl -sSf https://ziglang.org/download/community-mirrors.txt | shuf)

downloaded=false

for MIRROR in $MIRRORS
do
  ZIG_URL="$MIRROR/$ZIG_ARCHIVE"
  echo "Downloading $ZIG_URL"

  if curl -# -fL --retry 2 -o "$ZIG_ARCHIVE" "$ZIG_URL" &&
    xz -t "$ZIG_ARCHIVE"; then
    downloaded=true
    break
  fi

done

if [ "$downloaded" != true ]; then
  echo "Failed to download a valid Zig archive" >&2
  exit 1
fi


ZIG_DIR=$(basename $ZIG_ARCHIVE .tar.xz)

tar -xf "$ZIG_ARCHIVE"

sudo rm -rf "$INSTALL_DIR"
sudo mv "$ZIG_DIR" "$INSTALL_DIR"

sudo ln -sf "$INSTALL_DIR/zig" /usr/local/bin/zig

export PATH="/usr/local/bin:$PATH"
ls -l /usr/local/bin/zig

zig version
