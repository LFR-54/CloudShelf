#!/bin/zsh
# Renders the README and site screenshots (docs/images): the main window and the menu bar panel with demo
# accounts, light and dark, at 2x, then lists what changed against docs/images.
# Needs a Debug build in build/DerivedData, whose asset catalog holds the colors and logos.
# Usage: tools/screenshots/render.sh [output folder, build/screenshots by default]
set -euo pipefail
ROOT=${0:A:h:h:h}
HERE=${0:A:h}
OUT=${1:-$ROOT/build/screenshots}
APP=$ROOT/build/DerivedData/Build/Products/Debug/Docklume.app
[[ -d $APP ]] || { echo "Pas de build Debug dans build/DerivedData : compilez Docklume d'abord." >&2; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf $WORK; defaults delete readme-snap 2>/dev/null || true' EXIT

mkdir -p $WORK/Snap.app/Contents/MacOS
cp -R $APP/Contents/Info.plist $APP/Contents/Resources $WORK/Snap.app/Contents/
# The detail page shows the rclone flags, which depend on finding the bundled engine.
ln -s $APP/Contents/MacOS/rclone $WORK/Snap.app/Contents/MacOS/rclone
swiftc -swift-version 6 -Onone -suppress-warnings -module-name Docklume -target arm64-apple-macos15.0 \
  $ROOT/Docklume/{Engine,Model,Views}/**/*.swift $HERE/../Stubs.swift $HERE/main.swift \
  -o $WORK/Snap.app/Contents/MacOS/Docklume
swiftc -O $HERE/diff.swift -o $WORK/diff

# The window comes out 34 pt taller at random: render a few times and keep, for each image, a run whose height
# matches the committed one. Overlay scroll bars, or a connected mouse adds scroller gutters.
runs=(1 2 3 4 5 6)
for run in $runs; do
  mkdir $WORK/$run
  $WORK/Snap.app/Contents/MacOS/Docklume $WORK/$run -AppleShowScrollBars WhenScrolling 2> >(grep -v sandbox_extension >&2)
done
height() { sips -g pixelHeight $1 | awk '/pixelHeight/ { print $2 }' }
mkdir -p $OUT
for image in $WORK/1/*.png; do
  name=${image:t}
  pick=$image
  if [[ -f $ROOT/docs/images/$name ]]; then
    want=$(height $ROOT/docs/images/$name)
    for run in $runs; do
      if [[ $(height $WORK/$run/$name) == $want ]]; then pick=$WORK/$run/$name; break; fi
    done
  fi
  cp $pick $OUT/$name
done
$WORK/diff $ROOT/docs/images $OUT
echo "Images dans $OUT"
