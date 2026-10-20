#!/bin/sh

ARCH=$(arch)
VERSION="v0.0.1"
ARCHIVE_NAME="zerotty-$ARCH-linux-release.tar.gz"

curl -# -C -fL "https://codeberg.org/panda2code/zerotty/releases/download/$ARCH/$ARCHIVE_NAME"
