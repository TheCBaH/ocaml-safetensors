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
cat > "$client/dune-project" <<'EOF'
(lang dune 3.17)
(using melange 0.1)
EOF
if [ "$backend" = melange ]; then
  cat > "$client/dune" <<'EOF'
(melange.emit (target output) (modules main) (libraries safetensors-melange)
 (preprocess (pps melange.ppx)))
EOF
  cat > "$client/main.ml" <<'EOF'
let bytes : Adapter.Byte_buffer.t = [%mel.raw "new Uint8Array([2,0,0,0,0,0,0,0,123,125])"]
let () =
  assert (Result.is_ok (Adapter.Reader.of_uint8array bytes));
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
