#!/bin/sh
set -eu
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$PROJECT/.build/bridge"
python3 - "$STAGE" <<'PY'
import shutil, sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
PY
mkdir -p "$STAGE/mac" "$STAGE/android/app/src/main/res/drawable-nodpi"
cp "$PROJECT"/mac/*.js "$STAGE/mac/"
cp "$PROJECT/package.json" "$PROJECT/package-lock.json" "$STAGE/"
cp "$PROJECT/android/app/src/main/res/drawable-nodpi/companion.png" "$STAGE/android/app/src/main/res/drawable-nodpi/companion.png"
(cd "$STAGE" && npm ci --omit=dev --ignore-scripts)
