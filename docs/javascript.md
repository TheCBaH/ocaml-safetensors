# JavaScript backends

The standalone reader supports opt-in js_of_ocaml and Melange builds using
its existing byte-oriented Jsont decoder. Metadata integers remain exact
OCaml `int64` values; duplicate members and original byte locations survive
parsing. Native installations need no JavaScript compiler or npm packages.
mltorch integration is outside this project.

## Build and use

Open `.devcontainer/javascript/devcontainer.json` for the pinned toolchain:
OCaml 4.14.4, dune 3.24.2, Jsont 0.2.0, bytesrw 0.3.0,
js_of_ocaml 6.4.1, Melange 7.0.1-414 and Node 24.19.0. JavaScript development
dependencies and Chromium are locked through `javascript/package-lock.json`.

```sh
make js.submodules
make js.deps js.reference
make js.build.jsoo js.build.melange js.corpus
make test.javascript.offline
```

The build targets assemble independent dune projects below
`.cache/javascript/{jsoo,melange}`. `make test.js.install` installs each package
to an isolated prefix and builds an external dune client against installed
artifacts. The Melange target first installs the separately maintained
`melange-bigarray` dependency to `.cache/javascript/bigarray/installed`; include
that prefix's `lib` directory in `OCAMLPATH` when using another install prefix.
These packages are buildable locally; no public opam or npm release
has been made. To install explicitly:

```sh
cd .cache/javascript/jsoo # or melange
opam exec -- dune install --prefix /your/prefix safetensors-jsoo
# Melange: safetensors-melange
```

Link `safetensors-jsoo` or `safetensors-melange`. The wrapper module is `Safetensors_jsoo` or `Safetensors_melange`.
With `module Adapter = Safetensors_jsoo` (or the Melange wrapper), both expose:

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

The Melange build uses the independently installed
[melange-bigarray](https://github.com/TheCBaH/melange-bigarray) package at
`5ea1e7e2de4b55fa9be92da3765232f151be4720`. The Git submodule at `vendor/melange-bigarray` is pinned by the repository's
Git entry; `.gitmodules` records the upstream URL. Clone with
`git clone --recurse-submodules`, or run `make js.submodules` in an existing
checkout. The JavaScript devcontainer initializes it on creation and its CI
checkout is recursive. `make js.bigarray` verifies the checked-out commit and
clean submodule, builds in its Git-ignored `_build` directory, and installs
both `melange-bigarray` and its opt-in `melange-bigarray.compat` provider.
The Bigarray preparation target does not download or extract a release archive.
Native Dune builds exclude `vendor`; native package installs do not require
initializing this optional dependency. Required upstream license notices remain installed
with that dependency.

Jsont and bytesrw link `melange-bigarray.compat` consistently, so their plain
`Bigarray` types are identical to `Melange_bigarray` types. The existing public
`safetensors-melange.bigarray` library name forwards to this provider for older
Dune clients. New clients may link `melange-bigarray.compat` directly or use
`module Bigarray = Melange_bigarray`. The provider supplies the complete
in-memory Array0–3/Genarray API, complex kinds and shared views. Int/nativeint
storage is 32-bit; generic comparison/hash, Marshal, mmap and native ABI limits
follow the [polyfill's contract](https://github.com/TheCBaH/melange-bigarray/blob/main/docs/interop-and-ops.md).
Safetensors' public copy adapter retains its existing ownership contract.

Tests exercise typed narrowing, exact Int64 storage, overlap-safe blits,
complex multidimensional views and shared reshapes. Jsont bigarray decoding and
bytesrw slices use the installed provider; external clients additionally pass
arrays between those dependencies and the explicit `Melange_bigarray` module.
The port is confined to the optional build. Revisit the explicit Jsont patch
and submodule pin when updating sources or the compiler. Melange 5.1 failed
recursive Jsont initialization; the verified build requires Melange 7.

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
| JS-001 | Done | Real installed jsoo dependencies and shared core suite |
| JS-002 | Done | Injected fixtures; common Node/Chromium conformance runner |
| JS-003 | Done | Uint8Array copy adapter and ownership/invalid-buffer tests |
| JS-004 | Done | Real dependency compilation and explicit Jsont patch; original scoped Bigarray implementation superseded by JS-007 |
| JS-005 | Done | Optional Melange package and independent installed client |
| JS-006 | Done | Devcontainer workflows, offline conformance, native regressions and version/size/RSS reports |
| JS-007 | Done | Pinned installed melange-bigarray replaces bundled Array1; local Node/Chromium and offline installed clients passed; required CI gates main promotion |
| JS-008 | Done | Git submodule replaces Bigarray archive transport; recursive preparation, offline rebuild/install client and native checks passed locally; required CI gates main promotion |


## Completed CI evidence

Reader commit `66fc2950f49721b4aaf8ec94b68274e0acbbc9fc` passed
[all three devcontainer CI jobs](https://github.com/TheCBaH/ocaml-safetensors/actions/runs/36862925122)
on 2026-10-01. Both native compiler/dependency matrices passed, including the
minimum Dune 3.17.2/bytesrw 0.2.0 configuration. Fresh native package installation
uses its own opam root and compiler; external clients run with no runtime tools
on PATH and no networking. The 10,000-case native stress run passed with seed
1337. Committed feature locks keep both container configurations pristine.

JavaScript artifacts confirm Node 24.19.0 and Chromium 141.0.7390.37, with
45 cases and 337 tensor visits per backend per environment, plus 9 invalid
buffer cases in Node and 8 in Chromium. Both external installed clients passed.

| Backend | Conformance browser bundle (bytes) | Node test process peak RSS (bytes) |
| --- | ---: | ---: |
| jsoo | 3,265,776 | 581,472,256 |
| Melange | 1,569,612 | 574,353,408 |

These figures include test code, embedded fixtures and comparison allocations,
as described above. Artifacts `standalone-javascript` and `standalone-native`
contain the package/version reports, corpus hashes, byte comparisons, stress
result and independent-installation evidence. JS-001 through JS-006 are complete.


## Standalone Bigarray migration (2026-10-03)

JS-007 replaces the bundled Array1 implementation with the locked standalone
package. The authorized local JavaScript devcontainer passed both backends'
45 cases and 337 tensor visits in each of Node 24.19.0 and Chromium
141.0.7390.37. New shared-view, reshape, overlap and complex-array checks pass;
both installed clients pass offline. Native regression and formatting checks
also pass. These local reports record a development tree; promotion requires
the clean commit to pass all three
[required devcontainer jobs](https://github.com/TheCBaH/ocaml-safetensors/actions/workflows/build.yml).

Artifact `standalone-javascript` includes `melange-bigarray.json` with the
pinned submodule commit/path, clean state, compiler/provider prefix and `melange-install.json` with the
reader source SHA/cleanliness, installed dependency, emitted runtime module
and successful legacy-library/type-sharing checks. Existing backend reports
retain corpus counts, limits, browser versions, bundle sizes and peak RSS.
Native packages retain their compiler/dependency matrix and installation
contract; their opam dependencies do not gain a Melange requirement.


## Bigarray Git submodule (2026-10-03)

JS-008 replaces the Bigarray archive download/lock with the submodule pin at
`vendor/melange-bigarray`; the source stays at `5ea1e7e`. Local devcontainer
checks passed an offline dependency rebuild and installed Melange client,
including shared provider types, Jsont reshaping and bytesrw slices. Native
build/tests/formatting also passed with the initialized dependency excluded
from the native Dune tree. The submodule remained clean. `make clean` removes
its ignored build output. These development checks are separate from the
clean three-job CI gate required before main promotion.
