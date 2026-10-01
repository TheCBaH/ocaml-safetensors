# JavaScript backends

The standalone reader supports opt-in js_of_ocaml and Melange builds using
its existing byte-oriented Jsont decoder. Metadata integers remain exact
OCaml `int64` values; duplicate members and original byte locations survive
parsing. Native installations need no JavaScript compiler or npm packages.
mltorch integration is outside this project.

## Build and use

Open `.devcontainer/javascript/devcontainer.json` for the pinned toolchain:
OCaml 4.14.3, dune 3.24.2, Jsont 0.2.0, bytesrw 0.3.0,
js_of_ocaml 6.4.1, Melange 7.0.1-414 and Node 24.19.0. JavaScript development
dependencies and Chromium are locked through `javascript/package-lock.json`.

```sh
make js.deps js.reference
make js.build.jsoo js.build.melange js.corpus
make test.javascript.offline
```

The build targets assemble independent dune projects below
`.cache/javascript/{jsoo,melange}`. `make test.js.install` installs each package
to an isolated prefix and builds an external dune client against installed
artifacts. These packages are buildable locally; no public opam or npm release
has been made. To install explicitly:

```sh
cd .cache/javascript/jsoo # or melange
opam exec -- dune install --prefix /your/prefix safetensors-jsoo
# Melange: safetensors-melange
```

Link `safetensors-jsoo` or `safetensors-melange`. Both expose `Adapter.Reader`:

```ocaml
val of_uint8array :
  ?limits:Safetensors.Limits.t -> Adapter.Byte_buffer.t ->
  (Safetensors.Memory.t, Safetensors.Error.t) result
val copy_tensor :
  Safetensors.Memory.t -> string ->
  (Adapter.Byte_buffer.t, Safetensors.Error.t) result
```

For jsoo, `Adapter.Byte_buffer.t` is `Js_of_ocaml.Typed_array.uint8Array Js.t`.
For Melange it is an abstract JavaScript Uint8Array type. Melange's core is
available through `safetensors-melange.core`; jsoo uses the installed native
`safetensors` package compiled to JavaScript. Strings in the OCaml API contain
UTF-8 bytes, including tensor names. A JavaScript caller must encode/decode
text at the boundary; raw payloads never pass through text conversion. The
conformance entry points demonstrate that boundary and expose decimal strings
for shapes/offsets rather than compiler-specific int64 representations.

The adapter copies the exact Uint8Array view, including a Node Buffer view,
into owned OCaml storage. Tensor extraction returns another independent copy.
Detached, shared and resizable buffers and other view types produce structured
`invalid_argument` errors. Input copies are limited to 1,073,741,823 bytes
and the runtime's smaller string limit. Practical memory availability can
impose a substantially smaller ceiling. Allocation failures are runtime
exceptions, as with the native memory API. Caller-supplied limits bound header
parsing. Fetch, File/Blob, Node filesystem access and zero-copy numerical
views are outside this initial API.

## Melange dependency port and Bigarray

The build fetches hash-locked upstream Jsont and bytesrw releases and compiles
all their core/codec source. It never substitutes JSON.parse or an abbreviated
JSON decoder. Upstream ISC licenses are included in the extracted releases;
package installation retains their license notices. Two small Jsont changes
are applied by an explicit patch with zero fuzz:

- Rename the exception `Error` to `Decode_error` to avoid a JavaScript export
  collision with the `Error` module, updating codec catches consistently.
- Assign each generative type identifier a module-local integer UID instead
  of calling `Obj.Extension_constructor`, which Melange does not implement.
  The original extensible-variant equality witness stays intact.

A scoped `Bigarray.Array1` polyfill supplies the APIs used by Jsont and bytesrw.
It uses JavaScript typed arrays for float32/64, signed/unsigned 8/16-bit values,
int32, int64, int, nativeint and char. Int64 storage uses two 32-bit words and
OCaml int64 operations, preserving all 64 bits without Number conversion.
C and Fortran indexing, bounds checks, typed narrowing, `create`, `init`,
`dim`, `kind`, `layout`, `get`, `set` and unsafe access are implemented.
Melange int/nativeint storage is 32-bit. Complex kinds, multidimensional
Bigarrays, mapping, slicing and the rest of the native Bigarray API are not
provided. This is a dependency compatibility layer, not a general Bigarray
replacement; its public sublibrary name is `safetensors-melange.bigarray`.

Tests exercise Array1 directly and through Jsont bigarray decoding and bytesrw
slice conversion. The port is confined to the optional build. Revisit the
patch and polyfill when updating locked sources or the compiler. Melange 5.1
also failed recursive Jsont initialization; the verified build requires the
pinned Melange 7 compiler.

## Verification

`make js.corpus` prepares expectations with the native reader and pinned
safetensors 0.8.0 reference before offline JavaScript execution. Both backends
run the same 33 malformed core cases, all 13 dtypes, exact arithmetic, Unicode,
layout/limit checks and five embedded fixtures without filesystem access.
The shared runner then compares all names, metadata, decimal shapes/offsets,
error kinds/paths/byte offsets and every tensor byte across:

- Five synthetic files (18 tensors) and six immutable Hugging Face files
  (307 tensors, 3,114,833 bytes).
- All 26 upstream acceptance probes, preserving documented policy differences.
- Eight empty-tensor shape cases at 2^31, 2^32, 2^53 and signed-int64 boundaries.
- All 256 raw byte values, Unicode names, subviews, independent input/output
  ownership, Node Buffers, cross-realm Uint8Arrays and invalid buffers.

Node and headless Chromium run separately. CI executes tests inside a network
namespace without networking; browser requests are also blocked. Native Unix
lifecycle and sparse-file checks remain native tests. CI jobs all use the
repository's devcontainers and Makefile targets.

Reports in `.cache/reports/{jsoo,melange}.json` record exact Node/Chromium
versions, target limits, test bundle bytes and process peak RSS. Bundle figures
include the conformance program and embedded fixtures; RSS includes fixture
hex strings, comparisons and bundling, so neither measures production-only
reader overhead. The copy adapter necessarily holds the caller's input plus
an owned file copy and, during extraction, a tensor copy. No native large-file
parity or browser-engine coverage beyond tested Chromium is claimed.

## Execution tracker

| ID | Status | Evidence |
| --- | --- | --- |
| JS-001 | Implemented; CI pending | Real installed jsoo dependencies and shared core suite |
| JS-002 | Implemented; CI pending | Injected fixtures; common Node/Chromium conformance runner |
| JS-003 | Implemented; CI pending | Uint8Array copy adapter and ownership/invalid-buffer tests |
| JS-004 | Implemented; CI pending | Real dependency compilation; scoped Bigarray polyfill and explicit Jsont patch |
| JS-005 | Implemented; CI pending | Optional Melange package and independent installed client |
| JS-006 | CI pending | Devcontainer workflows, offline conformance, native regressions and version/size/RSS reports |
