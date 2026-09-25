#!/bin/sh
set -eu
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${TMPDIR:-/tmp}/platform-tools-windows.zip"
mkdir -p "$PROJECT/windows/platform-tools"
curl -L --fail https://dl.google.com/android/repository/platform-tools-latest-windows.zip -o "$ARCHIVE"
python3 - "$ARCHIVE" "$PROJECT/windows/platform-tools" <<'PY'
import sys, zipfile
from pathlib import Path
archive, output = sys.argv[1], Path(sys.argv[2])
with zipfile.ZipFile(archive) as source:
    for name in source.namelist():
        if name.startswith('platform-tools/') and not name.endswith('/'):
            target = output / name.split('/', 1)[1]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read(name))
PY
