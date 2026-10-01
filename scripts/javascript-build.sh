#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
backend=${1:?usage: javascript-build.sh jsoo|melange}
case "$backend" in jsoo|melange) ;; *) exit 2;; esac
root=$PWD
work=$root/.cache/javascript/$backend
mkdir -p "$work/adapter"
cp javascript/shared/{reader.ml,reader.mli,byte_buffer.mli} "$work/adapter/"
cp "javascript/$backend/byte_buffer.ml" "$work/adapter/"
cp javascript/shared/{describe.ml,test_bigarray.ml} test/core_cases.ml "$work/"
cp "javascript/$backend/main.ml" "$work/"
python3 - "$work" <<'PY'
import sys
from pathlib import Path
target = Path(sys.argv[1])
def literal(data):
    return '"' + ''.join('\\%03d' % c for c in data) + '"'
fixtures = sorted(Path('test/fixtures').glob('*.safetensors'))
(target/'fixtures.ml').write_text('let files = [\n' + ''.join(
    '(%s, %s);\n' % (literal(p.name.encode()), literal(p.read_bytes())) for p in fixtures) + ']\n')
PY
if [ "$backend" = jsoo ]; then
  sed -i 's/^type t$/type t = Js_of_ocaml.Typed_array.uint8Array Js_of_ocaml.Js.t/' "$work/adapter/byte_buffer.mli"
  opam exec -- dune build -p safetensors @install
  opam exec -- dune install --prefix "$root/.cache/javascript/native" safetensors
  export OCAMLPATH="$root/.cache/javascript/native/lib${OCAMLPATH:+:$OCAMLPATH}"
  cat > "$work/dune-project" <<'EOF'
(lang dune 3.17)
(package (name safetensors-jsoo))
EOF
  cat > "$work/adapter/dune" <<'EOF'
(library (name adapter) (public_name safetensors-jsoo)
 (libraries safetensors js_of_ocaml))
EOF
  cat > "$work/dune" <<'EOF'
(executable (name main) (modes js)
 (modules main core_cases fixtures describe test_bigarray)
 (preprocess (pps js_of_ocaml-ppx))
 (libraries safetensors safetensors-jsoo jsont.bytesrw bytesrw))
EOF
else
  download() {
    local name=$1 digest=$2
    local archive=$root/.cache/javascript/$name.tbz
    if [ ! -f "$archive" ]; then
      curl --fail --location --max-time 120 "https://erratique.ch/software/${name%-*}/releases/$name.tbz" -o "$archive.tmp"
      mv "$archive.tmp" "$archive"
    fi
    echo "$digest  $archive" | sha512sum --check
    tar -xjf "$archive" -C "$work"
  }
  download jsont-0.2.0 6206f73a66cb170b560a72e58f70b9fb2c20397b9ab819dceba49b6602b9b79e47ba307e6910e61ca4694555c66fdcd7a17490afb99548e8f43845a5a88913e7
  download bytesrw-0.3.0 388858b0db210a62a16f56655746fdfadbc64b22c2abb5ed5a12b2872e4f8c34f045cdb953a5dda9b92f0003c7f9f34d70fa5b5bb19fd32fb6121bbaeb7ceba0
  patch --batch --fuzz=0 -p1 -d "$work/jsont-0.2.0" < javascript/melange/jsont.patch
  mkdir -p "$work/core" "$work/polyfill"
  cp src/safetensors.{ml,mli} "$work/core/"
  cp javascript/melange/bigarray.ml "$work/polyfill/"
  cat > "$work/dune-project" <<'EOF'
(lang dune 3.17)
(using melange 0.1)
(package (name safetensors-melange))
EOF
  cat > "$work/polyfill/dune" <<'EOF'
(library (name bigarray_polyfill) (public_name safetensors-melange.bigarray)
 (wrapped false) (modules bigarray) (modes melange)
 (preprocess (pps melange.ppx)))
EOF
  cat > "$work/core/dune" <<'EOF'
(library (name safetensors) (public_name safetensors-melange.core)
 (modes melange) (libraries safetensors-melange.jsont safetensors-melange.codec))
EOF
  cat > "$work/adapter/dune" <<'EOF'
(library (name adapter) (public_name safetensors-melange)
 (modes melange) (libraries safetensors-melange.core)
 (preprocess (pps melange.ppx)))
EOF
  cat > "$work/dune" <<'EOF'
(subdir bytesrw-0.3.0/src
 (library (name bytesrw) (public_name safetensors-melange.bytesrw)
  (modules bytesrw bytesrw_fmt) (modes melange)
  (libraries safetensors-melange.bigarray) (flags (:standard -w -a))))
(subdir jsont-0.2.0/src
 (library (name jsont) (public_name safetensors-melange.jsont)
  (modules jsont jsont_base) (modes melange)
  (libraries safetensors-melange.bigarray) (flags (:standard -w -a))))
(subdir jsont-0.2.0/src/bytesrw
 (library (name jsont_bytesrw) (public_name safetensors-melange.codec)
  (modules jsont_bytesrw) (modes melange)
  (libraries safetensors-melange.jsont safetensors-melange.bytesrw)
  (flags (:standard -w -a))))
(melange.emit (target out)
 (modules main core_cases fixtures describe test_bigarray)
 (preprocess (pps melange.ppx))
 (libraries safetensors-melange safetensors-melange.core
  safetensors-melange.codec safetensors-melange.bytesrw))
(install (section doc) (package safetensors-melange)
 (files (jsont-0.2.0/LICENSE.md as jsont-LICENSE.md)
        (bytesrw-0.3.0/LICENSE.md as bytesrw-LICENSE.md)))
EOF
fi
cd "$work"
opam exec -- dune build --root . @all
