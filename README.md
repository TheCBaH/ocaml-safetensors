# OCaml Safetensors

A standalone, read-only OCaml library for safetensors. Jsont parses the JSON
header; the reader validates every tensor descriptor and exposes raw
little-endian bytes. No tensor framework, Python, or Rust is needed at runtime.

Two separately installable packages:

| Package / Dune library | OCaml module | Purpose |
| --- | --- | --- |
| `safetensors` | `Safetensors` | Header/index validation and memory reader; no Unix dependency. |
| `safetensors-unix` | `Safetensors_unix` | Owned Unix file handles, selected copies and bounded chunked reads. |

## Build and use

OCaml 4.14 or later, Dune 3.17 or later, Jsont 0.2.0 or later, and bytesrw
0.2.0 or later. From a checkout:

```sh
opam install . --deps-only --with-test
make build runtest
opam install .
```

The packages are not yet published to the public opam repository. To depend on
the installed file reader, add `(libraries safetensors-unix)` to your Dune
library or executable. Core-only clients use `(libraries safetensors)`.

```ocaml
let print_tensors path =
  Safetensors_unix.with_file path (fun reader ->
    let index = Safetensors_unix.index reader in
    List.iter
      (fun tensor ->
        Printf.printf "%s: %s, %Ld bytes\n"
          (Safetensors.Tensor.name tensor)
          (Safetensors.Dtype.to_string (Safetensors.Tensor.dtype tensor))
          (Safetensors.Tensor.byte_length tensor))
      (Safetensors.Index.tensors index);
    Ok ())
```

`Safetensors_unix.copy_tensor reader name` returns independent mutable bytes.
For a large tensor, use `read_into reader name ~tensor_offset buffer ~dst_off
~len`; offsets within tensors are int64. `with_file` closes the handle even
when its callback raises. Explicit `close` is idempotent; subsequent reads
return `Closed`. A handle's operations must be serialized, and its underlying
file must remain unchanged until it is closed. Copied bytes and index metadata
remain valid afterward. There is no mmap or implicit tensor conversion.

`Safetensors.Memory.of_string` validates an immutable complete file already in
memory. `Index.decode_header ~file_size` accepts only the header string and the
known total file size; `Index.header_length` validates the eight-byte prefix
before an application allocates that string. Header-only validation cannot
prove payload availability or authenticate file contents.

See [core interface](src/safetensors.mli) and
[Unix interface](unix/safetensors_unix.mli) for the full API.

## Format behavior

Supported types: `BOOL`, `U8`, `I8`, `U16`, `I16`, `U32`, `I32`, `U64`, `I64`,
`F16`, `BF16`, `F32`, `F64`. Shapes and offsets use exact nonnegative int64
values; JSON numeric tokens never pass through a lossy float-to-int conversion.
Scalars, zero-element tensors, arbitrary tensor names, and string metadata are
supported. Numeric values, including NaNs, infinities and boolean bit patterns,
are preserved as stored. Byte order is little-endian; layout is C-order.

All descriptors validate before any index is returned: required fields, unique
decoded names, checked byte counts, bounds, contiguous non-overlapping ranges,
and complete payload coverage. JSON whitespace may surround the header object.
Unknown tensor-record fields and unsupported dtypes are errors. Decimal integer
tokens must not contain fractions, exponents, signs, or string encodings.

`Error.t` exposes a stable kind, message, and available tensor/path/file-byte
context. Format and I/O failures return results; process resource exhaustion
and exceptions raised by application callbacks are not converted to results.
See [compatibility](docs/compatibility.md) for deliberate differences from the
reference implementation.

Default configurable limits are 100,000,000 header bytes, 100,000 tensors,
rank 64, 4,096 bytes per decoded JSON member name, 100,000 user-metadata entries,
and depth 16. The fixed decoding schema itself accepts at most three nested
containers. Builders reject excess members/elements during decoding; the
header-size cap bounds individual strings and decoder memory. A valid large
header can require several times its encoded size in memory. Reduce limits for
untrusted workloads. Copying one tensor is additionally bounded by OCaml's
maximum bytes allocation; chunked reads avoid that allocation limit.

## Verification

`make runtest` is offline and uses only OCaml plus 1.6 KB of project-owned
fixtures. It exercises all supported dtypes, exact integers, malformed files,
limits, short reads/EINTR, handle cleanup, an 8 GiB sparse file, and 1,000 seeded
byte-parity/property cases. `make test.stress` raises that budget to 10,000;
`SAFETENSORS_SEED` selects a replay seed. A failing generated case is reduced
by removing tensors and saved to `SAFETENSORS_FAILURE_FILE` (default
`property-failure.safetensors`). Arbitrary-byte and mutated-file cases must
also return without unexpected exceptions.

External conformance uses the upstream Rust-backed `safetensors.deserialize`
API; Torch and model inference are not involved. On Linux x86-64 or aarch64,
use CPython 3.13 and the pinned, hash-checked wheels:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --only-binary=:all: --require-hashes -r scripts/reference-requirements.txt
make test.interop
make fixtures.fetch
make test.hub
```

The Hub lock selects six files totaling **3,114,833 bytes and 307 tensors**.
Every tensor's bytes, dtype, shape, name, and metadata are compared through
memory, full-copy, and chunked access. The lock's discovery flags describe the
2026-09-29 investigation; execution evidence is written separately to
`.cache/reports/`. Downloads are bounded, revision-pinned and hash-checked on
fresh and cached reads. No model code or tokenizer is downloaded or executed.
The independently generated binary fixtures stay in Git; HF binaries do not.

`make test.standalone` archives the current Git commit, installs both packages
in a fresh opam switch, and builds external clients using only installed public
libraries. It compiles a disposable OCaml compiler and deletes that switch
on completion. CI executes the clients and conformance suite in isolated network
namespaces; runtime clients receive an empty environment with no Python/Rust
executable on `PATH`. The reference job and installation job are separate.

CI covers Linux x86-64 with OCaml 4.14.3/Jsont 0.2.0 and OCaml 5.3.0/Jsont 0.4.0,
plus the shared devcontainer. Local development also verifies Linux aarch64
with OCaml 4.14.3. Other platforms are not yet claimed as tested.

## Project scope

This release contains a standalone format reader. `mltorch` integration,
producer sidecars, downloads in the library, casts, serialization, shard-index
resolution, mmap, typed views, GPU access and JS/browser bindings are outside
scope. Future integrations need their own plan.

[Implementation tracker](ocaml-safetensors-tracker.md) ·
[Design](ocaml-safetensors-design.md) ·
[Verification research](ocaml-safetensors-verification.md) ·
[Fixture lock](ocaml-safetensors-fixtures.json)
