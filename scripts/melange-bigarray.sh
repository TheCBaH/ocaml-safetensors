#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
work=$root/.cache/javascript/bigarray
source=$root/vendor/melange-bigarray
prefix=$work/installed
pin=$(git ls-files --stage -- vendor/melange-bigarray | awk '$1 == "160000" && $3 == "0" {print $2}')
test -n "$pin"
test "$(git -C "$source" rev-parse HEAD)" = "$pin"
test -z "$(git -C "$source" status --porcelain --untracked-files=all)"
mkdir -p "$work"
python3 - "$source/_build" "$prefix" <<'PY'
import shutil
import sys
from pathlib import Path
for name in sys.argv[1:]:
    path = Path(name)
    if path.exists():
        shutil.rmtree(path)
PY
(
  cd "$source"
  opam exec -- dune build -p melange-bigarray @install
  opam exec -- dune install --root . --prefix "$prefix" melange-bigarray
)
test -z "$(git -C "$source" status --porcelain --untracked-files=all)"
mkdir -p "$root/.cache/reports"
python3 - "$prefix" "$pin" <<'PY'
import json
import subprocess
import sys
from pathlib import Path
lock = dict(repository=subprocess.check_output(['git', 'config', '-f', '.gitmodules', '--get', 'submodule.vendor/melange-bigarray.url'], text=True).strip(),
            path='vendor/melange-bigarray', commit=sys.argv[2], transport='git-submodule', dirty=False)
lock.update(ocaml=subprocess.check_output(['opam', 'exec', '--', 'ocamlc', '-version'], text=True).strip(),
            melange=subprocess.check_output(['opam', 'list', '--installed', '--short', '--columns=version', 'melange'], text=True).strip(),
            installed_prefix=sys.argv[1], provider='melange-bigarray.compat')
Path('.cache/reports/melange-bigarray.json').write_text(json.dumps(lock, indent=2) + '\n')
PY
