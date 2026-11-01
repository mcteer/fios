#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -e .env ]; then
  echo '.env already exists; credentials left unchanged.'
  exit 0
fi
umask 077
python3 - <<'PY'
from pathlib import Path
import secrets
text = Path('.env.example').read_text().replace('SESSION_SECRET=\n', 'SESSION_SECRET=' + secrets.token_hex(32) + '\n')
with Path('.env').open('x') as f:
    f.write(text)
PY
echo 'Created private configuration in .env. Open the workspace directly; no interface password is required.'
