#!/bin/zsh
# Checks the move from CloudShelf to Docklume on fake home folders: FormerName.migrate, then the adoption of the
# tag aliases CloudShelf made. Prints one line per check and fails if one does.
set -euo pipefail
ROOT=${0:A:h:h:h}
HERE=${0:A:h}
WORK=$(mktemp -d)
trap 'rm -rf $WORK' EXIT

for test in migration tags; do
  swiftc -swift-version 6 -Onone -suppress-warnings -module-name Docklume -target arm64-apple-macos15.0 \
    $ROOT/Docklume/{Engine,Model,Views}/**/*.swift $ROOT/Docklume/App/FormerName.swift \
    $HERE/../Stubs.swift $HERE/$test/main.swift -o $WORK/$test
  mkdir $WORK/$test-home
  $WORK/$test $WORK/$test-home
done
