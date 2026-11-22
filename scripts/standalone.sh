#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d -t safetensors-install-XXXXXXXX)
cleanup() {
  opam switch remove "$work/switch" --yes >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/source" "$work/client"
git -C "$root" archive HEAD | tar -x -C "$work/source"
compiler=$(ocamlc -version)
version=$(python3 "$work/source/scripts/package-version.py")
unset OPAMSWITCH
export OPAMROOT="$work/opam"
opam init --bare --no-setup --disable-sandboxing --yes
opam switch create "$work/switch" "ocaml-base-compiler.$compiler" --yes
opam pin add --switch "$work/switch" "safetensors.$version" "$work/source" --no-action --yes
opam install --switch "$work/switch" safetensors --with-test --yes
cat > "$work/client/dune-project" <<'DUNE'
(lang dune 3.17)
(name external_client)
DUNE
cat > "$work/client/dune" <<'DUNE'
(executable (name core) (modules core) (libraries safetensors))
DUNE
cat > "$work/client/core.ml" <<'ML'
let () =
  let limits = Result.get_ok (Safetensors.Limits.make ~max_header_bytes:256
      ~max_tensors:2 ~max_rank:3 ~max_name_bytes:32 ~max_metadata_entries:4 ()) in
  assert (Safetensors.Limits.max_header_bytes limits = 256);
  assert (Safetensors.Limits.max_tensors limits = 2);
  assert (Safetensors.Limits.max_rank limits = 3);
  assert (Safetensors.Limits.max_name_bytes limits = 32);
  assert (Safetensors.Limits.max_metadata_entries limits = 4);
  assert (Safetensors.Dtype.of_string "F8_E5M2" = Ok Safetensors.Dtype.F8_E5M2);
  assert (Safetensors.Dtype.byte_width Safetensors.Dtype.C64 = 8);
  let error = Safetensors.Error.make ~path:"$[\"x\"]"
      Safetensors.Error.Invalid_header "example" in
  assert (Safetensors.Error.json_path error = Safetensors.Error.path error);
  let header = {|{"x":{"dtype":"U8","shape":[1],"data_offsets":[0,1]}}|} in
  let prefix = Bytes.create 8 in
  Bytes.set_int64_le prefix 0 (Int64.of_int (String.length header));
  let data = Bytes.to_string prefix ^ header ^ "A" in
  match Safetensors.Memory.of_string data with
  | Error e -> failwith (Format.asprintf "%a" Safetensors.Error.pp e)
  | Ok r ->
      assert (Safetensors.Memory.copy_tensor r "x" = Ok (Bytes.of_string "A"));
      let view = Result.get_ok (Safetensors.Memory.tensor_view r "x") in
      assert (Bigarray.Array1.get view 0 = 'A');
      let backing = Bigarray.Array1.create Bigarray.char Bigarray.c_layout
          (String.length data) in
      String.iteri (Bigarray.Array1.set backing) data;
      let mapped = Result.get_ok (Safetensors.Memory.of_bigstring backing) in
      let view = Result.get_ok (Safetensors.Memory.tensor_view mapped "x") in
      assert (Bigarray.Array1.get view 0 = 'A');
      print_endline "installed core: independent memory reader"
ML
opam exec --switch "$work/switch" -- dune build --root "$work/client" core.exe
run_offline() {
  if [[ "${SAFETENSORS_REQUIRE_NETNS:-0}" == 1 ]]; then
    bash "$root/scripts/offline.sh" env -i PATH=/nonexistent "$@"
  else
    env -i PATH=/nonexistent "$@"
  fi
}
run_offline "$work/client/_build/default/core.exe"
opam pin add --switch "$work/switch" "safetensors-unix.$version" "$work/source" --no-action --yes
opam install --switch "$work/switch" safetensors-unix --with-test --with-doc --yes
opam exec --switch "$work/switch" -- dune build --root "$work/source" @doc
cat >> "$work/client/dune" <<'DUNE'
(executable (name reader) (modules reader) (libraries safetensors-unix examples))
(library (name examples) (modules examples) (libraries safetensors-unix))
DUNE
python3 - "$work/source/README.md" "$work/client/examples.ml" <<'PYTHON'
import re
import sys
from pathlib import Path
blocks = re.findall(r'^```ocaml\n(.*?)^```', Path(sys.argv[1]).read_text(), re.M | re.S)
assert blocks, 'README must provide installed-public OCaml examples'
Path(sys.argv[2]).write_text('\n'.join(blocks))
PYTHON
cat > "$work/client/reader.ml" <<'ML'
let () =
  match Safetensors_unix.with_file Sys.argv.(1) (fun r ->
    let index = Safetensors_unix.index r in
    assert (List.length (Safetensors.Index.tensors index) = 1);
    match Safetensors_unix.copy_tensor r "bits" with
    | Error e -> Error e
    | Ok b -> assert (Bytes.length b = 16); Ok ()) with
  | Ok () ->
      let view = Result.get_ok (Examples.view_from_file Sys.argv.(1) "bits") in
      Gc.full_major ();
      assert (Bigarray.Array1.dim view = 16);
      assert (Bigarray.Array1.get view 4 = '\x80');
      print_endline "installed Unix reader: descriptor and mmap views"
  | Error e -> failwith (Format.asprintf "%a" Safetensors.Error.pp e)
ML
opam exec --switch "$work/switch" -- dune build --root "$work/client" @all
run_offline "$work/client/_build/default/reader.exe" "$work/source/test/fixtures/bf16.safetensors"
lib=$(opam var --switch "$work/switch" lib)
mkdir -p "$root/.cache/reports"
opam exec --switch "$work/switch" -- sh "$root/scripts/namespace-check.sh" --fail \
  --prefix Safetensors --expect-libs "$root/scripts/namespace.expect" \
  "install=$lib/safetensors" "install=$lib/safetensors-unix" | tee "$root/.cache/reports/namespace.txt"
{
  printf 'reader commit: '
  git -C "$root" rev-parse HEAD
  printf 'network namespace required: %s\n' "${SAFETENSORS_REQUIRE_NETNS:-0}"
  printf 'installed packages:\n'
  opam list --switch "$work/switch" --installed --columns=name,version
} > "$root/.cache/reports/standalone.txt"
