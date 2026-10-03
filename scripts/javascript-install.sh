#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
backend=${1:?usage: javascript-install.sh jsoo|melange}
work=$root/.cache/javascript/$backend
prefix=$work/installed
client=$work/client
mkdir -p "$client"
cd "$work"
opam exec -- dune install --root . --prefix "$prefix" "safetensors-$backend"
export OCAMLPATH="$prefix/lib:$root/.cache/javascript/native/lib${OCAMLPATH:+:$OCAMLPATH}"
if [ "$backend" = melange ]; then
  export OCAMLPATH="$prefix/lib:$root/.cache/javascript/bigarray/installed/lib${OCAMLPATH:+:$OCAMLPATH}"
fi
cat > "$client/dune-project" <<'EOF'
(lang dune 3.17)
(using melange 0.1)
EOF
if [ "$backend" = melange ]; then
  cat > "$client/dune" <<'EOF'
(melange.emit (target output) (modules main)
 (libraries safetensors-melange safetensors-melange.bigarray
  safetensors-melange.jsont safetensors-melange.codec safetensors-melange.bytesrw)
 (preprocess (pps melange.ppx)))
EOF
  cat > "$client/main.ml" <<'EOF'
module Adapter = Safetensors_melange
let bytes : Adapter.Byte_buffer.t = [%mel.raw "new Uint8Array([2,0,0,0,0,0,0,0,123,125])"]
let () =
  assert (Result.is_ok (Adapter.Reader.of_uint8array bytes));
  let a = Melange_bigarray.Array1.init Melange_bigarray.float64
      Melange_bigarray.c_layout 4 float_of_int in
  let compatible : (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t = a in
  let view = Bigarray.Array1.sub compatible 1 2 in
  Bigarray.Array1.fill view 7.;
  assert (Melange_bigarray.Array1.get a 1 = 7.);
  let decoded = match Jsont_bytesrw.decode_string
      (Jsont.bigarray Bigarray.float64 Jsont.number) "[1.5,-2]" with
    | Ok a -> a | Error e -> failwith e in
  let decoded = Melange_bigarray.reshape_2 (Bigarray.genarray_of_array1 decoded) 1 2 in
  assert (Melange_bigarray.Array2.get decoded 0 1 = -2.);
  let bytes = Melange_bigarray.Array1.init Melange_bigarray.int8_unsigned
      Melange_bigarray.c_layout 2 (fun i -> 128 + i) in
  let slice = Bytesrw.Bytes.Slice.of_bigbytes bytes in
  assert (Bigarray.Array1.get (Bytesrw.Bytes.Slice.to_bigbytes slice) 1 = 129);
  print_endline "external installed Melange client passed"
EOF
  entry=$client/_build/default/output/main.js
else
  cat > "$client/dune" <<'EOF'
(executable (name main) (modules main) (modes js)
 (libraries safetensors-jsoo js_of_ocaml))
EOF
  cat > "$client/main.ml" <<'EOF'
open Js_of_ocaml
module Adapter = Safetensors_jsoo
let bytes = Js.Unsafe.js_expr "new Uint8Array([2,0,0,0,0,0,0,0,123,125])"
let () =
  assert (Result.is_ok (Adapter.Reader.of_uint8array bytes));
  print_endline "external installed jsoo client passed"
EOF
  entry=$client/_build/default/main.bc.js
fi
opam exec -- dune build --root "$client" @all
node "$entry"
mkdir -p "$root/.cache/reports"
opam list --installed --columns=name,version dune jsont bytesrw js_of_ocaml melange > "$root/.cache/reports/javascript-packages.txt"
printf 'independent installed %s client: passed\n' "$backend" > "$root/.cache/reports/$backend-install.txt"
if [ "$backend" = melange ]; then
  python3 - "$root" "$prefix" "$client" <<'PY'
import json
import subprocess
import sys
from pathlib import Path
root, prefix, client = map(Path, sys.argv[1:])
provider = root / '.cache/javascript/bigarray/installed'
runtime = client / '_build/default/output/node_modules/melange-bigarray/melange_bigarray.js'
assert runtime.is_file(), 'external client did not emit the installed polyfill'
assert 'melange-bigarray.compat' in (prefix / 'lib/safetensors-melange/META').read_text()
assert (provider / 'lib/melange-bigarray/META').is_file()
lock = json.loads((root / 'javascript/melange/bigarray.lock.json').read_text())
report = dict(source=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
              dirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True)),
              dependency=lock, installed_prefix=str(prefix), provider_prefix=str(provider),
              runtime_module=str(runtime.relative_to(client)),
              legacy_library='safetensors-melange.bigarray',
              dependency_type_identity=True, shared_views=True,
              jsont_reshape=True, bytesrw_slice=True)
(root / '.cache/reports/melange-install.json').write_text(json.dumps(report, indent=2) + '\n')
PY
fi
