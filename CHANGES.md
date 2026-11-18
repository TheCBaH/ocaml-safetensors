# Changes

## 0.1.0~dev — unreleased

- Add byte-aligned `F8_E5M2`, `F8_E4M3`, `F8_E8M0`, `F8_E4M3FNUZ`,
  `F8_E5M2FNUZ` and `C64` storage types, preserving raw bytes without numerical
  conversion. These extend the public `Dtype.t` variant; downstream exhaustive
  matches must account for the new constructors. Packed F4/F6 remain deferred.
- Use field-specific bounded codecs while retaining strict duplicate and
  unknown-field rejection. Remove the ineffective `Limits.make ~max_depth`
  option and add getters for every remaining configurable limit.
- Distinguish JSON syntax, schema, integer and resource-limit errors. Preserve
  semantic source locations, escape paths as JSON, and add `Error.json_path`
  while keeping `Error.path`. Error messages remain presentation text.
- Parse mapped headers once, avoid a redundant descriptor-header copy and
  include tensor/offset context on partial read failures. Document private
  writable COW mappings, unchanged-file requirements, possible fatal faults,
  GC lifetime and partially modified read destinations.
- Isolate header prefix decoding in a private module. Native and js_of_ocaml
  use `String.get_int64_le`; Melange uses explicit byte assembly to avoid its
  runtime's incorrect little-endian 64-bit reads. Add independent byte prefix
  checks and a 65,536-byte header regression.
- Guard memory tensor copies against the runtime's maximum bytes allocation.
  Expand string/bigstring/descriptor/mmap parity, boundary, sparse-file and
  replayable differential coverage. Large-file checks are explicit targets.
- Retain both owning JavaScript adapters, share typed-array validation and
  order preparation before parallel build/run/install consumers. Reject stale
  offline artifacts and record build/verification provenance.
- Derive oracle package versions from hash-pinned requirements, add dependency
  freshness checks and use the Dune project version for package tooling.

This is a pre-release API pass. The packages have not been published; no
release tag or registry publication is implied by these notes. See
[design](docs/design.md) and [compatibility](docs/compatibility.md) for policy
and scope.
