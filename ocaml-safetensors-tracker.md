# OCaml Safetensors implementation tracker

Updated: 2026-10-03. Repository: `TheCBaH/ocaml-safetensors`.
Current state: standalone implementation complete and promoted to `main`.
All required CI jobs passed for implementation commit `212181e`; the final
tracker-only update follows the same `devel` → CI → `main` workflow.

**Scope guard:** `mltorch` integration and producer sidecar handling are outside
this tracker. The release must be verified as a standalone library. A future
consumer effort needs a separate tracker and cannot be added to the v1 exit gate.

Links: [plan](ocaml-safetensors-plan.md) · [design](ocaml-safetensors-design.md) ·
[verification research](ocaml-safetensors-verification.md) ·
[fixture lock](ocaml-safetensors-fixtures.json).

## Status rules

- **Done:** the stated output and evidence exist; planning completion never means code completion.
- **Ready:** dependencies are satisfied; execution has not begun.
- **Planned:** waits for the listed prerequisite, with no claim of progress.
- **In progress / Blocked:** set only while executing; record the actual blocker and next action.

Implementation owner: Codex. Branch, commit, CI URL, and evidence are recorded
below; keep task IDs stable if mirrored to GitHub.
Never mark a skipped test, unavailable fixture, or source inspection as a passing
runtime verification.

## Research completed

| ID | Status | Output / evidence |
| --- | --- | --- |
| ST-001 | Done | Recommend `ocaml-safetensors`; authenticated repository lookup and public opam package-path lookup returned 404 on 2026-09-29. Naming rationale and caveats in plan. |
| ST-002 | Done | Inspect upstream release `0.8.0` and main `e246a256`; document runtime validation, unit/property tests, framework comparisons, fuzz harnesses, and CI. No upstream tests executed. |
| ST-003 | Done | Fetch and hash-check six pinned HF files: 3,114,833 file bytes, 3,081,652 payload bytes, 307 tensors. Actual header/dtype coverage recorded in lock. |
| ST-004 | Done | Remove consumer integration from v1 milestones and release gates; update whitespace policy based on released upstream tests. |
| ST-005 | Done | Create implementation sequence, acceptance criteria, dependencies, standalone validation matrix, and this tracker. |

## Implementation backlog

| ID | Milestone / task | Status | Depends on | Acceptance evidence required |
| --- | --- | --- | --- | --- |
| ST-010 | M0: Recheck names and bootstrap repository | Done | ST-001, ST-005 | Empty `main` root; implementation on `devel`; package identity/license set; scaffolding provenance preserved. |
| ST-011 | M0: Dune/opam/devcontainer/CI skeleton | Done | ST-010 | Green build/test/format on OCaml 4.14 and pinned 5.x; sshd present; generated files pristine; no application dependency. |
| ST-012 | M0: Pin and characterize upstream oracle | Done | ST-011 | Wheel/version/hash lock; executed minimal probes for whitespace, duplicates, unknown fields, integer syntax, empties; recorded compatibility table. |
| ST-020 | M1: Jsont exact-number/duplicate/limits proof | Done | ST-011, ST-012 | Original token extraction above 2^53; all decoded duplicates detected; bounded malformed nesting; minimum supported dependency versions demonstrated in CI. |
| ST-021 | M1: Public dtype/index/error interfaces | Done | ST-020 | Immutable index, all 13 dtypes, deterministic enumeration, structured errors, documented limits; API checks compile. |
| ST-022 | M1: Complete header/layout validation | Done | ST-021 | Prefix/header checks, exact integers, checked sizes, no gaps/overlaps/trailing payload; scalar/empty boundary fixtures pass. |
| ST-023 | M1: Malformed input and resource regressions | Done | ST-022 | Duplicate/Unicode/UTF-8/schema/overflow cases, early allocation limits, no leaked parser exceptions; bounded stress evidence. |
| ST-030 | M2: Memory reader | Done | ST-022 | Full validation before reads; exact independent copies; oversize/missing/empty behavior tested. |
| ST-031 | M2: Unix reader and handle lifecycle | Done | ST-030 | Same-descriptor reads, short-read/EINTR handling, truncation, bounded copies, bad ranges, idempotent close, no descriptor leaks. |
| ST-032 | M2: Test executable and access-path parity | Done | ST-031 | Index + raw extraction interface; memory/copy/chunked agreement; no payload copy at open; no alignment assumptions. |
| ST-040 | M3: Offline synthetic corpus and generator | Done | ST-012, ST-021 | All dtype/shape/metadata edge cases; under 1 MiB binary fixture budget; independent provenance and hand-calculated goldens; no network for `dune runtest`. |
| ST-041 | M3: Framework-free differential harness | Done | ST-032, ST-040 | `deserialize` oracle; compare every name/dtype/shape/byte sequence and metadata; explicit acceptance-difference table; synthetic CI green. |
| ST-042 | M3: Locked HF fetch/cache tooling | Done | ST-011, ST-003 | Anonymous immutable URLs; per-file/total cap; fresh/cache hash checks; atomic files; clear timeout/unavailable failure; no silent skip. |
| ST-043 | M3: Execute full HF conformance | Done | ST-041, ST-042 | Six files, 307 tensors; all bytes/metadata agree across access paths; lock digest + reference/reader versions in CI artifact. |
| ST-044 | M3: Properties and bounded fuzz replay | Done | ST-023, ST-041 | Seeded 1,000-case PR suite; 10,000-case scheduled target; scalar/zero shapes included; saved/shrunk failures; subprocess limits for stress. |
| ST-050 | M4: Independent package install smoke tests | Done | ST-032, ST-040 | Source tarball → clean opam switch → external Dune client; core works without Unix; file package independently installed; runtime works offline without Python/Rust/consumer repos. |
| ST-051 | M4: Documentation and support matrix | Done | ST-043, ST-044, ST-050 | API examples, exactness, dtype subset, limits, ownership, file mutation assumptions, tested compiler/platform list; no unsupported portability claims. |
| ST-052 | M4: Release readiness and promotion | Done | ST-011, ST-043, ST-044, ST-050, ST-051 | Same reader commit green across required jobs; no unreviewed oracle differences; clean logical commits; `devel` promoted only after evidence; registry updated. |

## Milestone gates

| Gate | Status | Required tasks |
| --- | --- | --- |
| M0 — Standalone skeleton and reference contract | Done | ST-010–012 |
| M1 — Exact, bounded Jsont header/index | Done | ST-020–023 |
| M2 — Memory and Unix bytes | Done | ST-030–032 |
| M3 — Independent conformance | Done | ST-040–044 |
| M4 — Standalone release readiness | Done | ST-050–052 |

Critical sequence: bootstrap → reference probes → Jsont proof → index validation
→ memory/Unix readers → differential conformance → release readiness.
Fixture-fetch tooling and synthetic generation can proceed once their individual
dependencies are met. This does not require parallel agents.

## Resolved decisions

| ID | Decision / uncertainty | Resolution |
| --- | --- | --- |
| D-01 | Name | Created `TheCBaH/ocaml-safetensors`; packages `safetensors` and `safetensors-unix`. |
| D-02 | Consumer scope | Exclude all `mltorch` and producer-sidecar implementation and testing. |
| D-03 | Reference | Pinned 0.8.0 wheels with hashes; 26 acceptance probes executed. |
| D-04 | Whitespace | Accept JSON whitespace around the root object, matching the released reader. |
| D-05 | Jsont exact integers and limits | Exact token extraction and bounded fixed-schema decoding implemented and tested. |
| D-06 | Duplicate/unknown-field differences | OCaml rejects; executed differences are recorded in docs/compatibility.md. |
| D-07 | HF corpus | Six files under 5 MiB suite / 2 MiB each; all 307 tensors compared byte-for-byte with the upstream reader. |
| D-08 | Offline fixtures | Synthetic project-owned binaries in Git; HF payloads fetched separately, not redistributed in package. |
| D-09 | Package independence | No Python/Rust/tensor framework at runtime; oracle remains test-only. |

## Execution evidence log

Evidence is recorded below; local results do not replace the final CI gate.

| Date | IDs | Evidence | Limit |
| --- | --- | --- | --- |
| 2026-09-29 | ST-001–005 | Plan, design amendments, verification report, fixture lock; full-file hashes and header summaries checked during research. | No library implementation, target build, upstream runtime test, or CI run. |

For each future task, append: date, task ID, owner, branch/commit, CI URL,
fixture-lock digest where relevant, outcome, and next action. Store large logs
as workflow artifacts and link them here. A release entry must identify the
exact source commit and all required passing jobs.

### 2026-10-01 implementation evidence (local)

Repository: https://github.com/TheCBaH/ocaml-safetensors; implementation branch
`devel`. Initial commit `0c6cbf7` compiled/tested in both CI compiler entries,
but the clean-tree check failed; `_opam/` is now ignored and failure diagnostics
print the actual diff/status. Final verification awaits the next CI run.

Local disposable devcontainer: OCaml 4.14.3, Jsont 0.2.0, Dune 3.24.2,
Python 3.13.5, safetensors 0.8.0, NumPy 2.2.6. Core: 13 dtypes, exact
integers, 33 malformed-header cases, five offline independent fixtures. Unix:
injected short reads/EINTR, truncation and descriptor cleanup, sparse 8 GiB
payload without large allocation. The reference harness checks 26 acceptance
probes, five synthetic files (18 tensors), and six HF files (307 tensors),
including all raw bytes across memory, copy, and chunked access. Hash-pinned
Python requirements and six downloader failure/cache tests are included.

The separately installable file library is named `safetensors-unix`, because
Dune assigns `safetensors.unix` to the core package by its name prefix.
This is an intentional correction to the initial naming proposal.

Clean source-package installation also passed locally: a fresh OCaml 4.14.3
switch installed each package separately and compiled external core and Unix
clients. Both clients ran with an empty environment and no runtime tools on
PATH. The 10,000-case stress run passed (seed 1337). CI additionally requires
network namespaces for external clients and differential verification.

### 2026-10-01 completed standalone verification

Implementation commit: `212181ee01a94b1a67138de57326fbc95ba6b0d5`.
[Required CI run](https://github.com/TheCBaH/ocaml-safetensors/actions/runs/36808144441)
passed all five jobs before promotion to `main`:

- Core build/tests/format and pristine generated files on OCaml 4.14.3 with
  Jsont 0.2.0/Dune 3.17.2, and OCaml 5.3.0 with Jsont 0.4.0/Dune 3.24.0.
- Shared devcontainer build, tests, and formatting.
- Network-isolated synthetic/reference/HF comparisons and 10,000-case stress
  (seed 1337); artifacts `standalone-conformance` include `synthetic.json`,
  `hub.json`, and `stress.txt`. Both reports record a clean reader tree.
- Fresh OCaml 4.14.3 switch, separately installed core and Unix packages,
  external Dune clients run in network namespaces with an empty environment
  and no runtime tools on PATH. Artifact `standalone-install` records the
  compiler/packages and `network namespace required: 1`.

Fixture-lock SHA-256:
`0e3284152d3a2dc9838fc44f96a5266c09b15a73c7259e4c100105a75993ad40`.
Reference-wheel lock SHA-256:
`076f9e5b514da83387768c0db9f26eb1069e1c506e973f0916881afb1ca72cc9`.
Every reference acceptance difference is asserted and documented in
[compatibility](docs/compatibility.md). ST-010 through ST-052 are complete.

The workspace registry records the repository and evidence. The authorized
local development container and build artifacts have been removed; no
Codespaces remain. No public opam submission or version tag is part of this
completion. `mltorch` integration remains explicitly outside this project.


### 2026-10-01 JavaScript backends completed

JS-001 through JS-006 are complete; implementation details, package usage and
measurements are maintained in [JavaScript backends](docs/javascript.md).
Reader commit `66fc295` passed all three devcontainer jobs in
[CI run 36862925122](https://github.com/TheCBaH/ocaml-safetensors/actions/runs/36862925122):
minimum/current native matrices, private-opam-root native installs, native
upstream/HF comparisons and 10,000 stress cases, both real Jsont JS backends
under Node 24.19.0/Chromium 141.0.7390.37 without networking, independent installed
JS clients and pristine source trees. The Melange Bigarray polyfill is scoped
to Array1; metadata integers and raw bytes retain the common reader semantics.
All build and verification helpers use Makefile targets. mltorch integration,
public opam/npm publication and release tags remain outside this delivery.


### 2026-10-03 Standalone Melange Bigarray migration

JS-007 uses `melange-bigarray` at locked revision `5ea1e7e`, installed in its
own prefix, for Jsont and bytesrw's plain Bigarray API. The bundled Array1
implementation is removed; `safetensors-melange.bigarray` forwards to the
installed compatibility provider. JavaScript OCaml advances to 4.14.4;
native dependency bounds and matrices remain unchanged. Shared views,
reshape, complex arrays, exact overlapping Int64 copies and explicit/provider
module type identity are exercised alongside the reader's existing corpus.
Local devcontainer Node/Chromium tests, offline installed clients and native
regression/format checks pass. Main promotion is gated on the same three
required CI jobs. [Maintained verification details](docs/javascript.md#standalone-bigarray-migration-2026-10-03).
