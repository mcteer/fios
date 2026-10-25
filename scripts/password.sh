#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
for line in Path('.env').read_text().splitlines():
    if line.startswith('FIOS_PASSWORD='):
        print(line.split('=', 1)[1])
PY
