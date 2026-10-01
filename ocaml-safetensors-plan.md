# OCaml Safetensors implementation plan

Status: ready for implementation planning; implementation has not started.  
Updated: 2026-09-29.  
Scope: independently packaged, tested, and released safetensors reader using Jsont.

## Name and deliverables

Recommend **`TheCBaH/ocaml-safetensors`** for the GitHub repository, with description
“Standalone OCaml reader for safetensors, with Jsont metadata parsing.” Use
**OCaml Safetensors** as the project title. The name states both language and
format and fits the existing `ocaml-*` repositories. A coined name would make
format discovery harder without providing a useful distinction.

Use `safetensors` / `Safetensors` for the core package/library/module and
`safetensors-unix` / `safetensors-unix` / `Safetensors_unix` for file access.
On 2026-09-29, authenticated GitHub lookup returned 404 for the proposed repo,
repository searches for `ocaml-safetensors` and `safetensors-ocaml` returned no
results, and the public opam registry had no `packages/safetensors` directory.
These are availability observations, not reservations. Recheck at bootstrap.
There is already an OCaml `nx.safetensors` module; avoid claims that this is the
first OCaml implementation. Its existence does not occupy the proposed package.
[Existing API](https://ocaml.org/p/nx/1.0.0~alpha1/doc/nx.safetensors/Safetensors/index.html).

Deliverables in this planning change:

- [Design](ocaml-safetensors-design.md): API and behavioral contract, updated scope.
- [Tracker](ocaml-safetensors-tracker.md): stable task IDs, dependencies, acceptance evidence.
- [Verification research](ocaml-safetensors-verification.md): upstream findings and corpus rationale.
- [Fixture lock](ocaml-safetensors-fixtures.json): six real, pinned, hash-checked files.

These local documents are the tracker for now. Creating a GitHub repository,
issues, or a Projects board is an implementation/bootstrap task; none was
created by this planning work. If a board is used later, mirror the task IDs
and call it **OCaml Safetensors — standalone reader**.

## Scope and completion boundary

**`mltorch` integration is explicitly excluded.** There are no tasks to change
`mltorch`, interpret its graph types, parse the producer's `safetensors.json`
sidecar, download application weights, perform dtype conversion, or run model
inference. `devcontainer.pytorch-image-models` is a motivating future consumer,
not a build dependency, test dependency, fixture source requirement, or release
gate. A future integration must have its own plan and tracker.

V1 implements:

- Strict Jsont parsing of tensor descriptors and optional `__metadata__`.
- Exact nonnegative int64 dimensions/offsets, checked layout arithmetic, limits,
  immutable indexes, and structured errors.
- The 13 byte-sized dtypes listed in the design, including raw F16/BF16 bits.
- An in-memory reader and a separately installable Unix reader with bounded
  copies/chunked reads and explicit ownership.
- Offline synthetic tests, independent upstream differential tests, the small
  Hub corpus, and installation tests from a standalone source distribution.

Writer, mmap, typed tensor views, remote HTTP reading in the library, GPU APIs,
shard resolution, FP8/complex/packed dtypes, and JS/browser support are deferred.
A small conformance executable is test infrastructure, not a commitment to a
public CLI product. One selected Hub fixture is a shard file: testing its bytes
as a single safetensors file does not add shard-index support.

## M0 — Bootstrap and reference contract

Tasks: `ST-010`–`ST-012`.

1. Recheck names; create the standalone repository with an empty `root` commit
   on `main`, then work on `devel`, following the empty-root bootstrap convention.
   Import suitable scaffolding history using `git cherry-pick -x`; adapt it to
   this package instead of carrying another project's dependencies.
2. Establish Dune-generated opam metadata, license/authorship, `.mli` boundaries,
   formatter pin, Makefile aliases, and OCaml 4.14 plus one pinned 5.x CI entry.
   Use the shared OCaml feature/action and sshd-enabled devcontainer. Add a
   clean-opam job outside the devcontainer to expose accidental dependencies.
3. Pin the release oracle to `safetensors==0.8.0`, resolve wheel hashes and Python
   version, and characterize ambiguous cases in Actions. Record a compatibility
   table with small input bytes and observed outcomes. Source research is not
   a substitute for executing these probes.

Exit: an empty-but-installable skeleton has green build/test/format CI; the
reference environment is reproducible, and compatibility choices have fixtures.
The published package must not require Python or Rust at runtime.

## M1 — Prove Jsont parsing and validation

Tasks: `ST-020`–`ST-023`; depends on M0.

Implement a narrow prototype before committing to the entire API. Prove that
Jsont provides original numeric token locations, sees every object-member
occurrence, and permits early bounded rejection. Use the raw decimal token,
not its rounded float, for exact int64 parsing. Include numbers immediately
above 2^53, escaped/non-ASCII names before numeric fields, and repeated escaped
equivalents of object keys. Establish minimum Jsont/Dune versions from CI.

Use member folds/maps that enforce duplicates, required/unknown fields, and
bounded accumulation. Never accept a lossy string map as evidence of unique
keys. If locations or limits cannot be implemented with the chosen codec,
resolve that dependency gap before the general decoder; do not silently reduce
precision or add a second JSON parser.

Then implement dtype/index/error modules and complete layout validation. Include
header/payload bounds, checked products/additions, scalar and zero-element
rules, empty ranges, and deterministic enumeration. No index is returned until
all tensor records validate, including unrequested tensors.

Compatibility decisions to encode as tests:

| Topic | Planned policy |
| --- | --- |
| Whitespace | Accept leading/trailing JSON space, tab, CR, LF like release 0.8.0; one root object and no other trailing content. Supersedes the original space-only draft. |
| Duplicate decoded keys | Reject at every object level even if the reference accepts some. |
| Unknown tensor fields | Reject; root entries remain arbitrary tensor names except `__metadata__`. |
| Integer values | Decimal nonnegative integer tokens only; exact signed-int64 range; no float truncation, strings, fractions, exponent notation, or negative zero. |
| Resource limits | Enforce the design's configurable limits during decoding and host allocation checks regardless of configuration. |
| Huge zero-element shapes | Validate dimensions, then detect any zero before checked multiplication. Record reference differences if multiplication order rejects a mathematically empty tensor. |
| Unsupported dtype | Explicit error, including for empty tensors; no guessed width. |

Exit: adversarial parser fixtures pass at both compiler versions; exactness,
resource bounds, and duplicate rejection have executable evidence. API review
can proceed without unresolved numeric or parsing assumptions.

## M2 — Memory and Unix readers

Tasks: `ST-030`–`ST-032`; depends on validated index.

Implement memory reading from immutable strings and Unix open/header/read/close.
Use one owned descriptor, large-file size/seek APIs, short-read loops, and
exception-safe cleanup. Reads are copies; chunked `read_into` supports tensors
larger than one OCaml allocation. Return errors for oversized copies, bad
ranges, truncated input, and closed handles. No concurrent operations on one
handle unless serialized by the caller.

The conformance executable lists index data and writes requested tensor bytes
using only the library. The external harness computes hashes; the library does
not gain a cryptographic dependency merely for verification. Test arbitrary
chunk boundaries, unaligned offsets, empty reads, descriptor leaks, and errors
mid-read. Assert header-only opening does not copy payloads, using instrumented
read accounting in tests rather than only timing a small model.

Exit: memory, full file copies, and chunked reads agree on every synthetic
tensor; the example reads a local safetensors file without a tensor framework.

## M3 — Independent verification

Tasks: `ST-040`–`ST-044`; starts after M0, completion requires M2.

### Offline synthetic corpus

Keep fixtures small and project-owned; target under 1 MiB total committed binary
data. Generate valid fixtures with a pinned independent writer and retain
provenance. Use raw-byte construction for malformed headers and boundary cases;
hand-calculate several tiny expected values so a reference implementation bug
cannot redefine all expectations. Use NumPy for standard dtype generation and
an independently validated raw BF16 fixture. Add no production OCaml writer.

Coverage includes all supported dtypes, scalar/empty shapes, Unicode and escaped
keys, metadata absent/empty/present, all JSON whitespace, arbitrary record order,
unusual alignment, NaN/Inf/signed-zero bits, malformed schemas, truncation,
overlap/gaps/trailing bytes, arithmetic boundaries, and limits. Reference-only
unsupported dtypes become explicit rejection fixtures. Add regression tests for
I/O errors and handle lifecycle separately from binary format validation.

### Differential oracle and Hub corpus

Use `safetensors.deserialize` from the pinned Python wheel for raw dtype/shape/
payload results; it calls the Rust reader and handles BF16 without Torch.
Compare every tensor's bytes or digest, not floating-point approximations.
Optional string metadata is checked separately. The detailed oracle contract
and six-file selection are in [verification research](ocaml-safetensors-verification.md).

Implement a lock-driven fetcher with bounded transfers, anonymous immutable URLs,
cache revalidation, atomic downloads, and clear failure reporting. The complete
corpus is 3,114,833 bytes and 307 tensors. Its downloader belongs to test tooling,
not either installable library. Pin expectations to the lock digest; updating
remote fixtures requires an explicit manifest/expectation diff.

### Properties and fuzz regressions

Use QCheck or an equivalent OCaml test-only dependency for bounded valid layouts
and mutations. Proposed PR budget: 1,000 seeded cases; scheduled budget: 10,000,
with seed and minimized failures preserved. Compare generated valid files from
an independent writer to both readers; mutate offsets, lengths, schema tokens,
and member ordering. Require no unexpected exceptions and deterministic results.
Run arbitrary-byte/deep-nesting stress tests in a subprocess with time and memory
bounds. Assert limit rejection rather than crashing the shared CI runner.

Exit: all six Hub files match the reference for every tensor through all access
paths; synthetic edge cases pass; every acceptance difference is documented;
no new unexplained differences remain. A missing download or skipped fixture
cannot count as conformance success.

## M4 — Standalone installation and release readiness

Tasks: `ST-050`–`ST-052`; depends on M3.

Install from a source tarball into a clean opam switch, then compile a tiny
out-of-tree Dune program against installed public libraries. Test the core
package without Unix, then core + Unix. Disable network for its actual execution
and offline tests. Assert no `mltorch`, producer checkout, vendored tensor
runtime, Python, NumPy, or Rust is needed by that executable. The external
reference tools run in their own CI job.

Document API examples, limits, dtype subset, byte order, copy semantics, file
mutation assumptions, concurrency, errors, and tested platform matrix. Initially
claim Linux x86-64 at the two tested compiler versions; include a macOS Unix
job before claiming macOS. Add other platforms only with corresponding evidence.

Before a release candidate, require core tests, property tests, complete Hub
conformance, and standalone packaging jobs green on the same reader commit.
Promote clean logical commits from `devel` to `main`, and record the evidence in
the tracker. Tagging/publication follows the repository's release workflow;
this planning task does not publish anything. Release readiness ends here;
`mltorch` adoption is not a prerequisite.

## CI jobs and failure policy

| Job | Trigger / inputs | Required evidence |
| --- | --- | --- |
| `core` | Push/PR/dispatch; offline synthetic fixtures; OCaml 4.14 + pinned 5.x | Build, unit/property tests, formatting, pristine generated files. |
| `standalone-install` | Push/PR/dispatch; clean switch/source tarball | Independently installed public packages and external example, no consumer/runtime checkout. |
| `interop` | Push/PR/dispatch; pinned wheel and synthetic files | Byte-exact differential results and reviewed compatibility differences. |
| `hub-conformance` | `devel`/`main` pushes, dispatch, schedule | All six locked files, verified hashes, 307 tensors; required for promotion/release. PRs changing fixtures or I/O should run it too. |
| `stress` | Schedule/dispatch, short seeded subset in `core` | Bounded fuzz/property report and replayable regressions. |

Acquire test inputs first; run reader tests offline afterward. Distinguish
infrastructure failure, malformed fixture, oracle disagreement, and reader
failure. Do not collapse all of them into “model load failed.” Include the
reader commit, tool versions, fixture-lock hash, and seeds in artifacts.

Expose these planned Makefile targets so local and CI entry points agree:
`make build`, `make runtest`, `make format`, `make test.interop`,
`make fixtures.fetch`, `make test.hub`, `make test.standalone`, and
`make test.stress`. The fetch target performs network I/O; the test targets use
already acquired inputs. These targets do not exist yet.

Use GitHub Actions for known commands, and
`bin/cs ci -R TheCBaH/ocaml-safetensors -b devel` for the first CI diagnosis. No target builds
on this host. Use a Codespace only for exploration; stop it between commands and
delete it when no active work needs it. Keep scratch pushes from triggering CI.
No PR is created unless requested.

## Definition of done

The standalone v1 is complete when M0–M4 have recorded passing evidence, the
public package installs independently, exact metadata and byte access meet the
design, the six-file corpus and synthetic cases are verified against a pinned
upstream implementation, and the supported subset/limits are documented. Research
checks in this workspace establish fixture provenance only. They do not mark
any OCaml implementation milestone complete.
