# Standalone OCaml safetensors reader

Status: design proposal; implementation scoped by the standalone plan; no library or GitHub repository created.  
Date: 2026-09-29.  
Recommended repository: `TheCBaH/ocaml-safetensors`.  
Proposed opam package / Dune library / module: `safetensors` / `safetensors` / `Safetensors`.
Availability checked on 2026-09-29; names remain unreserved until bootstrap.
See the [implementation plan](ocaml-safetensors-plan.md),
[task tracker](ocaml-safetensors-tracker.md), and
[verification research](ocaml-safetensors-verification.md).

## Purpose and boundaries

Build a small, standalone OCaml library that reads a `.safetensors` file,
validates its JSON header using **Jsont**, and exposes named tensors as dtype,
shape, and raw little-endian bytes. A future consumer is `mltorch`, loading
pretrained weights for graphs exported by `devcontainer.pytorch-image-models`.
**Consumer integration is outside this implementation plan.** The library is
built, verified, and released independently of both projects, Python, PyTorch,
or a model catalogue. External reference tooling is a separate test dependency.

Version one provides header inspection, complete layout validation, in-memory
reading, and a native Unix file reader with bounded tensor copies. It does not
write checkpoints, download from Hugging Face, execute tensor operations, cast
weights, load pickle, or interpret graph schemas. Sharded checkpoints, typed
Bigarray views, mmap, and browser integration are later extensions. Keeping
mmap out of the initial API avoids promising alignment, lifetime, and concurrent
file-mutation guarantees before a consumer needs it.

## Evidence from this workspace

These are inspected checkout facts, not claims about the current GitHub default
branches:

| Example | Relevant convention or contract |
| --- | --- |
| `repos/opickle`, `2040ef8` | Standalone parser; OCaml >= 4.14; Dune-generated opam metadata; bytesrw; optional application-facing CLI pattern; cram tests; Makefile build/test/format targets. |
| `repos/jsont.dune` | Dune names `jsont` and `jsont.bytesrw`; the latter exposes `Jsont_bytesrw` and depends on bytesrw. Its upstream source submodule is uninitialized here. |
| `repos/mltorch`, `cab6f95` | Existing Jsont descriptions in `lib/generated/pytorch_weights_config.ml`; `test/parse_weights_config.ml` uses `Jsont_bytesrw.decode_string`. `opickle` is consumed as a vendored submodule. |
| `repos/devcontainer.pytorch-image-models`, `ad25047` | `scripts/weights_map.py` produces schema-version-1 `models/safetensors.json`; `schemas/safetensors.schema.json` is the contract. |
| `repos/ocaml-devcontainer`, `ccb162c` | Shared OCaml scaffolding; use its history and the shared feature/action packages when bootstrapping. |

The producer's sidecar is distinct from the JSON header inside a checkpoint.
It names a pinned source (`repo_id`, `revision`, `filename`, `url`, `sha256`,
`size`), maps graph names to checkpoint `key`, `dtype`, and `shape`, and lists
`unmapped` constants. It is also distinct from Hugging Face's sharded
`model.safetensors.index.json`.

For example, the inspected `repvit_m1_0` map points to
`timm/repvit_m1_0.dist_300e_in1k` revision
`94445f5481b027599200e61ed5e108dbaedc0139`. Its batch-normalization counter is
an `I64` scalar with `shape: []`; its floating weights are `F32`. This is a
useful small metadata fixture, not a reason to commit the 29,519,376-byte
checkpoint to the new library.

The producer has five graph trees: ordinary models and fp16/bf16 cast/autocast
variants. A cast graph can require a different floating dtype from its checkpoint.
Autocast graph names can carry `model.`; the sidecar already resolves that name
to the checkpoint key. Consumers must use the mapping verbatim.

## Package structure

Use one source repository with independently installable packages:

| Package / public library | Responsibility | Runtime dependencies |
| --- | --- | --- |
| `safetensors` / `safetensors` | Header decoding, validation, immutable index, in-memory bytes | OCaml stdlib, Jsont, bytesrw (`jsont.bytesrw`) |
| `safetensors-unix` / `safetensors-unix` | Open a regular file, read header, seek and copy selected payloads | `safetensors`, Unix |

Start with OCaml 4.14 compatibility because the consumer uses that generation.
Select the minimum Dune and Jsont versions by compiling the parser prototype,
then record explicit bounds in `dune-project`. Do not claim compatibility merely
because a combinator exists in the current online documentation. Use public
opam dependencies for releases; a pinned `jsont.dune` development dependency is
an integration option, not a reason to embed a second JSON implementation.

Suggested layout:

```text
src/                  Safetensors: dtype, header/index, errors, memory reader
unix/                 Safetensors_unix: file ownership and selected reads
test/                 malformed inputs, small synthetic fixtures, cram
test/fixtures/        binary fixtures plus expected metadata and byte hashes
scripts/              pinned Python fixture generator / interoperability check
examples/             list names and copy one tensor
.devcontainer/        shared OCaml feature, sshd, tool/version locks
.github/workflows/    build/test/format, interoperability, container publication
```

Any future sidecar decoder and graph adapter belong to a separate consumer
project and plan. This format package does not parse producer-specific sidecars.
A separate CLI package may be added if inspection is useful; it is not required
for the first library release.

## Format contract and validation

The upstream format consists of an unsigned little-endian 8-byte header length
`N`, `N` bytes of UTF-8 JSON, and tensor payload bytes. Tensor offsets are
half-open and relative to the payload start, `8 + N`. The header contains one
JSON object; this reader accepts surrounding JSON whitespace, matching the
released reference reader's tests rather than the README's narrower wording. Tensor records have `dtype`, `shape`,
and `data_offsets`; optional `__metadata__` holds string-to-string metadata.
Storage is little-endian and C-order. Duplicate keys, overlapping payloads,
and holes are invalid; scalar and zero-element tensors are supported.
See the [upstream format](https://github.com/safetensors/safetensors#format).

The proposed reader applies these additional explicit implementation policies:

1. Read exactly eight prefix bytes. Reject an unsigned length outside the
   supported signed-int64 range before arithmetic. Check `N <= file_size - 8`
   and the configured header limit before allocating. Never convert an
   unchecked int64 to OCaml `int`.
2. Read exactly `N` header bytes. Require one JSON object, allowing only JSON
   whitespace (space, tab, CR, LF) before and after it. Reject any other trailing
   content. Do not require a particular header alignment. Jsont handles syntax
   and UTF-8. This updates the initial stricter draft after inspection of the
   released upstream whitespace tests; see the verification research.
3. Reject duplicate decoded member names at every object level, including
   equivalent escaped names. Require all three tensor fields exactly once;
   reject unknown tensor-record fields for v1. Arbitrary root names are tensor
   names except the reserved `__metadata__` name. Metadata values must be strings.
4. Parse dimensions and offsets as exact nonnegative integer tokens. Store them
   as int64, restricted to `0 .. Int64.max_int`; report larger values as an
   implementation limit. Reject strings, fractions, exponent notation, and
   negative tokens rather than coercing them.
5. Require two offsets with `0 <= begin <= end <= payload_size`. Calculate
   byte counts with checked multiplication. A scalar has one element. Validate
   every dimension first; if any is zero the count is zero, without overflowing
   on other dimensions. Otherwise reject product overflow.
6. Require `end - begin = element_count * dtype_width`. Sort by `(begin, end)`
   and walk from cursor zero, requiring each `begin = cursor`, then advancing
   to `end`. Sorting the end as well handles empty tensors at shared boundaries.
   Require the final cursor to equal the payload size. An empty header or
   metadata-only header therefore requires an empty payload.
7. Expose an index only after all records and the complete layout validate,
   including tensors the caller did not request. Header-only validation uses
   the supplied total file size; it cannot prove payload availability or content.

V1 supports byte-sized formats needed by the producer, plus conventional
unsigned integer types:

| Bytes per element | Dtypes |
| --- | --- |
| 1 | `BOOL`, `U8`, `I8` |
| 2 | `U16`, `I16`, `F16`, `BF16` |
| 4 | `U32`, `I32`, `F32` |
| 8 | `U64`, `I64`, `F64` |

Other names return `Unsupported_dtype`, even for empty tensors. FP8, complex,
and packed sub-byte formats need deliberate additions and reference fixtures;
this is a documented subset, not a claim to support every evolving upstream
dtype. F16/BF16 are exposed as their stored bits. Structural validation does not
scan numerical values, reject NaN/Inf, or normalize boolean bytes.

Default policy limits: 100,000,000 header bytes, 100,000 tensors, rank 64,
4,096 decoded bytes per JSON member name, and JSON nesting depth 16. Make limits
configurable with hard host-allocation checks that cannot be disabled. These
are resource policies, not format restrictions. Enforce count/rank/depth limits
during parsing, before constructing unbounded intermediate lists. Document
memory amplification from the header representation.

## Jsont decoding strategy

Use `Jsont_bytesrw.decode_string' ~locs:true` over the bounded header string.
Retain structured errors and translate their paths/locations into the library's
error type. Jsont exposes source locations, but its ordinary numeric mappings
use floats and integer mappings can truncate or accept strings. Its object
codec normally uses the last duplicate member. Neither default is the required
safetensors policy. See [Jsont numeric types](https://erratique.ch/software/jsont/doc/Jsont/index.html#numbers)
and [codec behavior](https://erratique.ch/software/jsont/doc/Jsont_bytesrw/index.html).

The first implementation milestone is a small parser proof:

- Use bounded Jsont object-member folds/maps that see every occurrence, check
  decoded-name uniqueness, and then construct the typed record. Do not start
  with `Object.as_string_map`, which can erase evidence of duplicate names.
- For integer fields, use a custom Jsont number mapping with node metadata.
  Recover the original token from the retained header string using
  `Meta.textloc`, `Textloc.first_byte`, and `Textloc.last_byte` (inclusive).
  Validate decimal integer syntax and accumulate into int64 with overflow
  checks; ignore the rounded float value. This supports offsets above 2^53
  without depending on float round-trips or implementing a JSON parser.
- Verify actual token locations with whitespace, escaped names, and non-ASCII
  names before the number. Check that duplicate callbacks see both occurrences,
  including required fields and `__metadata__`.
- Use fixed-depth schema descriptions and bounded array/member accumulators.
  Unknown nested structures must fail promptly; test decoder behavior before
  promising the depth limit. A bounded generic `Jsont.json` prototype is useful
  to inspect member preservation, but an unrestricted AST is not the production
  resource-limit solution.

[Jsont metadata](https://erratique.ch/software/jsont/doc/Jsont/Meta/index.html)
and [Textloc](https://erratique.ch/software/jsont/doc/Jsont/Textloc/index.html)
document the location mechanism. Its suitability for exact token extraction
and bounded decoding remains a prototype acceptance gate. If the selected
Jsont version cannot provide it, resolve that in the codec integration before
publishing; never silently round, stringify the source JSON, or substitute a
second JSON parser.

Drop the raw header and temporary decoder structures after constructing the
validated index. Header metadata here means both tensor descriptors and optional
`__metadata__`; Jsont parses all of it.

## Proposed API and ownership

The following is an interface sketch, not compiled code:

```ocaml
module Safetensors : sig
  module Error : sig
    type t
    val pp : Format.formatter -> t -> unit
  end
  module Limits : sig
    type t
    val default : t
    (* Constructor/setters validate custom limits. *)
  end
  module Dtype : sig
    type t = Bool | U8 | I8 | U16 | I16 | U32 | I32 | U64 | I64
           | F16 | BF16 | F32 | F64
    val byte_width : t -> int
  end
  module Tensor : sig
    type t
    val name : t -> string
    val dtype : t -> Dtype.t
    val shape : t -> int64 list
    val data_offsets : t -> int64 * int64
    val byte_length : t -> int64
  end
  module Index : sig
    type t
    val decode_header :
      ?limits:Limits.t -> file_size:int64 -> string -> (t, Error.t) result
    val metadata : t -> (string * string) list
    val tensors : t -> Tensor.t list
    val find : t -> string -> Tensor.t option
    val data_start : t -> int64
  end
  module Memory : sig
    type t
    val of_string : ?limits:Limits.t -> string -> (t, Error.t) result
    val index : t -> Index.t
    val copy_tensor : t -> string -> (bytes, Error.t) result
  end
end

module Safetensors_unix : sig
  type t
  val open_file :
    ?limits:Safetensors.Limits.t -> string ->
    (t, Safetensors.Error.t) result
  val index : t -> Safetensors.Index.t
  val copy_tensor : t -> string -> (bytes, Safetensors.Error.t) result
  val read_into :
    t -> string -> tensor_offset:int64 -> bytes -> dst_off:int -> len:int ->
    (unit, Safetensors.Error.t) result
  val close : t -> unit
end
```

`decode_header` receives only the exact `N` header bytes and the total file
size; it derives `N` from the string length. File and memory constructors handle
the prefix. Index enumeration uses deterministic bytewise name order. Shapes
and records are immutable; callers cannot mutate a validated index. Reading by
name ensures a descriptor from another file cannot accidentally select bytes.

The memory reader retains its immutable input; tensor copies are independent
and mutable. The Unix reader owns one descriptor, checks regular-file size via
large-file APIs, and reads only the prefix/header at open. It copies payloads
on demand; `read_into` supports tensors too large for one OCaml allocation.
A copy request exceeding `Sys.max_string_length` returns a limit error before
allocating. A zero-byte read succeeds without accessing payload storage.

Use the same open descriptor throughout; do not reopen by path between header
validation and payload access. Loop over short reads, handle interrupted reads,
and return truncation on unexpected EOF. Initial seek/read implementation is
not safe for concurrent operations on one handle; callers serialize access or
open independent handles. Provide a bracketed helper for exception-safe cleanup.
`close` is idempotent; later reads return `Closed`. Previously copied data and
immutable index metadata remain usable.

Files must stay unchanged for a handle's lifetime. This reader does not promise
snapshot isolation or authenticity; same-size concurrent writes are not reliably
detectable. A future mmap API needs separate ownership and mutation rules.

Expose structured errors with a stable kind, optional tensor name, file byte
position, JSON path, and explanatory text. Minimum kinds: I/O, truncated input,
invalid header/JSON, duplicate member, invalid integer, unsupported dtype,
invalid offsets, size mismatch, resource limit, missing tensor, and closed handle.
Expected malformed input returns `result`, not leaked decoder exceptions.

## Future consumers (outside this project)

`mltorch` and `devcontainer.pytorch-image-models` provide useful motivation and
schema examples, but no integration work is included in the standalone reader's
plan, tracker, tests, or release gates. The producer's sidecar is not part of
the safetensors binary format. Future cache/download, SHA-256 verification,
graph-name mapping, dtype conversion, and missing-constant behavior belong in
a separately planned consumer adapter.

The public API exposes enough information for that future work: exact names,
dtypes, shapes, metadata, and raw bytes. Standalone conformance uses synthetic
fixtures and small public Hugging Face files, without loading any model graph
or requiring a consumer checkout.

## Verification plan

Normal `dune runtest` uses tiny committed fixtures and no network or Python.
Generate valid fixtures independently with pinned Python `safetensors` and
NumPy; keep the generator, versions, expected names/shapes/dtypes, payload
hashes, and fixture provenance. Construct BF16 bit fixtures separately if the
chosen generator lacks support. Do not require Torch for the library's normal
build. The reference-only job uses the pinned Python extension's raw
`deserialize` API, avoiding framework conversion even for BF16.

Required cases:

- Every supported dtype; scalar; zero-sized dimension in every position;
  metadata-only/empty file; Unicode names; unsorted header records; shared
  empty boundaries; NaN/Inf bit preservation.
- Short prefix/header/payload; oversized unsigned prefix; bad UTF-8/JSON;
  missing/unknown fields; duplicate and escape-equivalent keys at each level;
  incorrect metadata types; malformed offsets and unsupported dtypes.
- Gaps, overlap, reverse ranges, extra trailing payload, shape/byte mismatch,
  arithmetic overflow, and configured limits reached at and beyond boundaries.
- Exact integers around 2^53 and Int64.max_int using header-only/synthetic
  sources; fractions that round to integers, exponent forms, and negative zero.
  No multi-petabyte fixture allocation is needed.
- Chunked reads, invalid destination bounds, repeated close/read-after-close,
  partial-read and I/O failure injection, and release of descriptors on errors.
- Differential acceptance against the pinned reference reader for the declared
  subset; document intentional stricter behavior rather than blindly copying
  reference bugs. Compare payload bytes, not only printed floating values.

A standalone interoperability job compares synthetic fixtures and a separate
Hub job verifies every tensor in the six pinned files in
[the fixture lock](ocaml-safetensors-fixtures.json): 3,114,833 bytes total,
307 tensors. The [verification report](ocaml-safetensors-verification.md)
documents actual dtype/layout coverage and upstream testing. Property tests
mutate small headers and assert bounded failures. No consumer model execution
is part of verification.

## GitHub and development workflow

Use the existing `opickle` and `ocaml-devcontainer` projects as concrete
scaffolding references. When implementation starts, follow
the empty-root bootstrap convention: create an empty `root` commit on `main`,
then develop on `devel`. Transfer reusable scaffolding commits with
`git cherry-pick -x` and retain local adaptations; do not copy a whole unrelated
project. Use generated opam metadata, a pinned formatter, shared
`ghcr.io/thecbah/ocaml-features/ocaml:1`, and the sshd feature before Codespaces.

The initial GitHub Actions workflow should:

- Trigger on push, pull request, and workflow dispatch; use read-only default
  permissions and cancel superseded runs on the same ref.
- Check out required submodules and use
  `TheCBaH/devcontainer-action/devcontainer@v1`, as the inspected parser does.
- Run `make build`, `make runtest`, `make format`, then verify a pristine tree,
  including generated opam files and fixture outputs.
- Test the OCaml 4.14 floor and one explicitly pinned OCaml 5.x version; add a
  plain opam installation check outside the devcontainer to catch undeclared
  dependencies. Add macOS Unix-reader coverage before claiming that platform.
- Keep interoperability and image publishing separate. Restrict package-write
  permission and publication to trusted branches; PR tests need no secrets.
- Configure Dependabot for GitHub Actions and devcontainer dependencies, and
  submodules only if introduced. Select action versions/SHAs at bootstrap time;
  the versions in inspected examples are not a permanent lock recommendation.

Known build/test commands run in Actions. Diagnose failures first with
`bin/cs ci -R TheCBaH/ocaml-safetensors -b devel` (or `-p` when reviewing a PR).
Use Codespaces only for exploration, stop between commands, and delete them as
soon as no active task needs them. Scratch pushes use `refs/scratch/*` or
`[skip ci]`. No local target build is part of this design task.

Promote clean logical commits from `devel` to `main` only after CI is green;
create no PR unless requested. Confirm release licensing/metadata, test the
source tarball with opam, and publish a tagged release only after standalone
installation, synthetic tests, and full locked-corpus conformance pass. Record landed and pending state in
[the implementation tracker](ocaml-safetensors-tracker.md).

## Delivery milestones and decisions

1. **Parser proof:** establish exact token locations, duplicate detection,
   bounded decoding, and supported Jsont version. Pass the adversarial cases
   before committing to the public interface.
2. **Standalone reader:** implement core/index, memory and Unix reads, docs,
   synthetic fixtures, and green GitHub CI. Prove no model runtime dependency.
3. **Independent conformance:** pinned upstream differential oracle, synthetic
   properties, and all tensors in the small Hugging Face corpus through memory
   and Unix access paths.
4. **Standalone release:** source-package installation and external-client tests,
   clean history, and documentation of limits/platforms. No consumer integration.

Proposed defaults are a read-only format library, exact int64 metadata,
copy-based payload access, and strict validation. Remaining implementation
gates are Jsont codec behavior, minimum dependency versions, final package-name
availability at bootstrap, and executed upstream conformance probes. mmap, shard indexes, remote range
access, and additional dtypes require separate evidence and API review.
