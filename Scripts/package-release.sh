#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
ARCHIVE="release/MacCleaner-$VERSION.zip"

VERSION="$VERSION" ./build-app.sh
mkdir -p release
rm -f "$ARCHIVE"
ditto -c -k --keepParent build/MacCleaner.app "$ARCHIVE"

echo "릴리스 파일: $ARCHIVE"
shasum -a 256 "$ARCHIVE"
