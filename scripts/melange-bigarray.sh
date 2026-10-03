#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
work=$root/.cache/javascript/bigarray
source=$work/source
prefix=$work/installed
mapfile -t lock < <(python3 - <<'PY'
import json
from pathlib import Path
lock = json.loads(Path('javascript/melange/bigarray.lock.json').read_text())
for key in ['commit', 'url', 'sha256']:
    print(lock[key])
PY
)
archive=$work/${lock[0]}.tar.gz
mkdir -p "$work"
if [ ! -f "$archive" ]; then
  curl --fail --location --max-time 120 "${lock[1]}" -o "$archive.tmp"
  mv "$archive.tmp" "$archive"
fi
echo "${lock[2]}  $archive" | sha256sum --check
python3 - "$source" "$prefix" <<'PY'
import shutil
import sys
from pathlib import Path
for name in sys.argv[1:]:
    path = Path(name)
    if path.exists():
        shutil.rmtree(path)
PY
mkdir -p "$source"
tar -xzf "$archive" --strip-components=1 -C "$source"
(
  cd "$source"
  opam exec -- dune build -p melange-bigarray @install
  opam exec -- dune install --root . --prefix "$prefix" melange-bigarray
)
mkdir -p "$root/.cache/reports"
python3 - "$prefix" <<'PY'
import json
import subprocess
import sys
from pathlib import Path
lock = json.loads(Path('javascript/melange/bigarray.lock.json').read_text())
lock.update(ocaml=subprocess.check_output(['opam', 'exec', '--', 'ocamlc', '-version'], text=True).strip(),
            melange=subprocess.check_output(['opam', 'list', '--installed', '--short', '--columns=version', 'melange'], text=True).strip(),
            installed_prefix=sys.argv[1], provider='melange-bigarray.compat')
Path('.cache/reports/melange-bigarray.json').write_text(json.dumps(lock, indent=2) + '\n')
PY
