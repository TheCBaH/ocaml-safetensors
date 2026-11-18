# OCaml Safetensors

[![build](https://github.com/TheCBaH/ocaml-safetensors/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/TheCBaH/ocaml-safetensors/actions/workflows/build.yml)
[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/TheCBaH/ocaml-safetensors)

A standalone, read-only OCaml library for safetensors. Jsont parses the JSON
header; the reader validates every tensor descriptor and exposes raw
little-endian bytes. No tensor framework, Python, or Rust is needed at runtime.

Two separately installable packages:

| Package / Dune library | OCaml module | Purpose |
| --- | --- | --- |
| `safetensors` | `Safetensors` | Header/index validation and memory reader; no Unix dependency. |
| `safetensors-unix` | `Safetensors_unix` | Owned Unix file handles, bounded chunked reads and private file mappings. |

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
return `Closed`. A handle's operations must be serialized: reads seek and use
the same descriptor position. On EOF or I/O failure, `read_into` may already
have changed part of the requested destination range; it does not roll back.
Copied bytes and index metadata remain valid after closing.

`Safetensors.Memory.of_string` validates an immutable complete file already in
memory and retains it. `Memory.of_bigstring` retains the supplied bigarray
without copying the payload. `Memory.tensor_view` returns an alias for a
bigstring-backed reader, but allocates a fresh bigarray for a string-backed
reader. `Memory.copy_tensor` always returns independent mutable bytes.

For example, these functions use only installed public libraries; link
`safetensors` for the first two, and `safetensors-unix` for file mapping:

```ocaml
let ( let* ) = Result.bind

let copy_from_string file name =
  let* reader = Safetensors.Memory.of_string file in
  Safetensors.Memory.copy_tensor reader name

let view_from_bigstring backing name =
  let* reader = Safetensors.Memory.of_bigstring backing in
  Safetensors.Memory.tensor_view reader name

let view_from_file path name =
  let* reader = Safetensors_unix.Mmap.open_file path in
  Safetensors.Memory.tensor_view reader name
```

Keep borrowed bigstrings and their views unmodified while a reader or view is
in use. The bigarray type permits writes; it does not enforce this contract.
The memory reader and each alias keep the underlying storage alive, so a view
survives dropping the reader and garbage collection. Keeping even a small
alias may retain an entire large buffer or mapping.

`Mmap.open_file` maps the whole regular file privately with writable
copy-on-write pages. Writes through a view violate the reader contract: they
can affect other views of the same mapping, although they do not write back to
the file. The descriptor is closed before `open_file` returns. There is no
explicit unmap operation; the GC eventually releases the mapping after its
reader and all views become unreachable.

Both Unix readers require the underlying file to remain unchanged for their
whole lifetime, including the lifetime of mapped views. Neither supplies a
snapshot of a changing file. Truncating a mapped file can cause a fatal
`SIGBUS` when its pages are accessed, rather than a structured error. The
descriptor reader can return `Truncated` on EOF, but a rewrite may still yield
new bytes under stale metadata. Use immutable published files, synchronization,
or an independently acquired stable copy when consistency is required.

`Index.decode_header ~file_size` accepts only the header string and the
known total file size; `Index.header_length` validates the eight-byte prefix
before an application allocates that string. Header-only validation cannot
prove payload availability or authenticate file contents.

See [core interface](src/safetensors.mli) and
[Unix interface](unix/safetensors_unix.mli) for the full API.

## Format behavior

Supported types: `BOOL`, `U8`, `I8`, `U16`, `I16`, `U32`, `I32`, `U64`, `I64`,
`F16`, `BF16`, `F32`, `F64`, `F8_E5M2`, `F8_E4M3`, `F8_E8M0`,
`F8_E4M3FNUZ`, `F8_E5M2FNUZ`, `C64`. Packed `F4`, `F6_E2M3` and `F6_E3M2`
are not supported. Shapes and offsets use exact nonnegative int64
values; JSON numeric tokens never pass through a lossy float-to-int conversion.
Scalars, zero-element tensors, arbitrary tensor names, and string metadata are
supported. Numeric values, including NaNs, infinities and boolean bit patterns,
are preserved as stored. Byte order is little-endian; layout is C-order.

All descriptors validate before any index is returned: required fields, unique
decoded names, checked byte counts, bounds, contiguous non-overlapping ranges,
and complete payload coverage. JSON whitespace may surround the header object.
Unknown tensor-record fields and unsupported dtypes are errors. Decimal integer
tokens must not contain fractions, exponents, signs, or string encodings.

`Error.t` exposes a machine-readable kind and available tensor/JSON-path/file-byte
context. `Error.json_path` and `Error.path` access the same JSON path; the latter
is retained for compatibility. Messages and `Error.pp` are presentation text,
including upstream decoder diagnostics, and may vary with dependency versions.
Format and I/O failures return results; process resource exhaustion
and exceptions raised by application callbacks are not converted to results.
See [compatibility](docs/compatibility.md) for deliberate differences from the
reference implementation.

Default configurable limits are 100,000,000 header bytes, 100,000 tensors,
rank 64, 4,096 bytes per decoded JSON member name, and 100,000 user-metadata
entries. There is no configurable depth limit: the strict fixed schema accepts
at most three nested containers and rejects unexpected value sorts. Builders
reject excess members/elements during decoding; the header-size cap bounds
individual strings and decoder memory. A valid large header can require
several times its encoded size in memory. Reduce limits for
untrusted workloads. Copying one tensor is additionally bounded by OCaml's
maximum bytes allocation; chunked reads avoid that allocation limit.

## Verification

`make runtest` is offline and uses only OCaml plus small project-owned
fixtures. It exercises all supported dtypes, exact integers, malformed files,
limits, short reads/EINTR, handle cleanup and 1,000 seeded
byte-parity/property cases. `make test.stress` raises that budget to 10,000;
`SAFETENSORS_SEED` selects a replay seed. A failing generated case is reduced
by removing arbitrary tensors and saved to `SAFETENSORS_FAILURE_FILE` (default
`property-failure.safetensors`), with a minimized file and replay details.

Large sparse-file checks run separately with `make test.large-file`. They
probe selected bytes beyond 2 GiB without copying the complete tensor, and check sparse-file support and
disk budget first. Unsupported environments report an explicit skip; ordinary
`runtest` and `opam install --with-test` do not create an 8 GiB file.
`make test.copy-limit-32` checks the copy-allocation guard only when run by a
true 32-bit OCaml runtime; another runtime fails the target so it cannot
produce a misleading portability result.

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

The synthetic suite also runs seeded differential valid, arbitrary-byte and
targeted header mutations. `SAFETENSORS_FUZZ_CASES` controls its case budget
(default 100), and `SAFETENSORS_SEED` controls replay. Unexpected exceptions,
oracle disagreements and byte/descriptor mismatches save original and
predicate-preserving minimized files in `.cache/reports/failures/`, alongside
JSON replay details including seed, case, mutation location, limits and versions.

The Hub lock selects six files totaling **3,114,833 bytes and 307 tensors**.
Every tensor's bytes, dtype, shape, name, and metadata are compared through
string and bigstring memory readers, descriptor copies/chunks and mapped views.
The lock's discovery flags describe the 2026-09-29 investigation; execution
evidence is written separately to
`.cache/reports/`. Downloads are bounded, revision-pinned and hash-checked on
fresh and cached reads. No model code or tokenizer is downloaded or executed.
The independently generated binary fixtures stay in Git; HF binaries do not.

`make test.standalone` archives the current Git commit, installs both packages
in a fresh opam switch, and builds external clients using only installed public
libraries. It compiles a disposable OCaml compiler and deletes that switch
on completion. CI executes the clients and conformance suite in isolated network
namespaces; runtime clients receive an empty environment with no Python/Rust
executable on `PATH`. The reference job and installation job are separate.

The pinned native CI matrix uses Linux x86-64 with OCaml 4.14.3/Jsont 0.2.0
and OCaml 5.3.0/Jsont 0.4.0 through the repository's devcontainers. Additional
jobs resolve current dependencies and exercise the copy bound on a true 32-bit
OCaml runtime, retaining package/compiler reports. Local development has also
used Linux aarch64 with OCaml 4.14.3. Other platforms are not yet claimed as tested.

## Project scope

This release contains a standalone format reader. `mltorch` integration,
producer sidecars, downloads in the library, numerical casts and typed tensor
decoding, serialization, shard-index resolution and GPU access are outside
scope. Raw bigstring views, private mmap and the optional JavaScript adapters
are included. See [design](docs/design.md) for validation and ownership rationale.

[Fixture lock](ocaml-safetensors-fixtures.json)

Optional [JavaScript backends](docs/javascript.md) compile the same Jsont
reader with js_of_ocaml or Melange. Both provide copying Uint8Array adapters;
`make test.javascript` verifies Node, Chromium and external installed clients.
Native packages retain their independent toolchain and dependency requirements.
