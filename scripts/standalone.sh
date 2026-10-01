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
opam switch create "$work/switch" "ocaml-base-compiler.$compiler" --yes
opam pin add --switch "$work/switch" safetensors.0.1.0 "$work/source" --no-action --yes
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
  let header = {|{"x":{"dtype":"U8","shape":[1],"data_offsets":[0,1]}}|} in
  let prefix = Bytes.create 8 in
  Bytes.set_int64_le prefix 0 (Int64.of_int (String.length header));
  let data = Bytes.to_string prefix ^ header ^ "A" in
  match Safetensors.Memory.of_string data with
  | Error e -> failwith (Format.asprintf "%a" Safetensors.Error.pp e)
  | Ok r ->
      assert (Safetensors.Memory.copy_tensor r "x" = Ok (Bytes.of_string "A"));
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
opam pin add --switch "$work/switch" safetensors-unix.0.1.0 "$work/source" --no-action --yes
opam install --switch "$work/switch" safetensors-unix --with-test --yes
cat >> "$work/client/dune" <<'DUNE'
(executable (name reader) (modules reader) (libraries safetensors-unix))
DUNE
cat > "$work/client/reader.ml" <<'ML'
let () =
  match Safetensors_unix.with_file Sys.argv.(1) (fun r ->
    let index = Safetensors_unix.index r in
    assert (List.length (Safetensors.Index.tensors index) = 1);
    match Safetensors_unix.copy_tensor r "bits" with
    | Error e -> Error e
    | Ok b -> assert (Bytes.length b = 16); Ok ()) with
  | Ok () -> print_endline "installed Unix reader: independent BF16 bytes"
  | Error e -> failwith (Format.asprintf "%a" Safetensors.Error.pp e)
ML
opam exec --switch "$work/switch" -- dune build --root "$work/client" reader.exe
run_offline "$work/client/_build/default/reader.exe" "$work/source/test/fixtures/bf16.safetensors"
mkdir -p "$root/.cache/reports"
{
  printf 'reader commit: '
  git -C "$root" rev-parse HEAD
  printf 'network namespace required: %s\n' "${SAFETENSORS_REQUIRE_NETNS:-0}"
  printf 'installed packages:\n'
  opam list --switch "$work/switch" --installed --columns=name,version
} > "$root/.cache/reports/standalone.txt"
