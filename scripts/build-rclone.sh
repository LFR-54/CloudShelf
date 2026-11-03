#!/bin/zsh
# Builds the rclone bundled with CloudShelf: the release below with the patches in rclone-patches,
# for Apple Silicon, with macFUSE support. Needs Go (~/.local/go or on the PATH) and macFUSE installed.
set -euo pipefail
VERSION=v1.75.2
BUILD=cloudshelf.7
ROOT=${0:A:h:h}
SRC=$ROOT/rclone
export PATH=$HOME/.local/go/bin:$PATH

if [[ ! -d $SRC ]]; then
  git clone -q --depth 1 --branch $VERSION https://github.com/rclone/rclone.git $SRC
fi
cd $SRC
[[ $(git describe --tags --exact-match HEAD) == $VERSION ]] || { echo "rclone/ n'est pas sur $VERSION" >&2; exit 1; }
git reset -q --hard && git clean -q -fd
for patch in $ROOT/rclone-patches/*.patch; do git apply $patch; done
CGO_ENABLED=1 go build -tags cmount -trimpath \
  -ldflags "-s -X github.com/rclone/rclone/fs.Version=$VERSION-$BUILD" \
  -o $ROOT/build/rclone/rclone .
# Signed on its own, without the hardened runtime of the app, so it can load macFUSE's libfuse.
codesign --force --sign - $ROOT/build/rclone/rclone
$ROOT/build/rclone/rclone version | head -1
