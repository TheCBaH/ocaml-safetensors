# OCaml Safetensors

A standalone, read-only OCaml library for safetensors, using Jsont to parse
metadata and returning raw little-endian tensor bytes. No tensor framework,
Python, or Rust dependency is required at runtime.

The implementation is in development on `devel`. See the
[implementation tracker](ocaml-safetensors-tracker.md) and
[design](ocaml-safetensors-design.md). Consumer integration is out of scope.

Libraries: `safetensors` (`Safetensors`) and the separately installable
`safetensors-unix` (`Safetensors_unix`).

```sh
opam install . --deps-only --with-test
make build runtest format
```

See [verification research](ocaml-safetensors-verification.md) for the pinned
upstream oracle and small Hugging Face corpus. The file reader copies requested
bytes; callers serialize operations on a handle and keep the file unchanged
while it is open.
