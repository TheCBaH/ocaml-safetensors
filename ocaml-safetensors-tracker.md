# OCaml Safetensors implementation tracker

Updated: 2026-09-29. Repository recommendation: `TheCBaH/ocaml-safetensors`.  
Current state: planning/research complete; no implementation repository, code,
CI run, GitHub issues, or Projects board created by this task.

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

Implementation tasks are unassigned. When work begins, record an owner, branch,
commit, CI URL, and evidence below; keep task IDs stable if mirrored to GitHub.
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
| ST-010 | M0: Recheck names and bootstrap repository | Ready | ST-001, ST-005 | Empty `main` root; implementation on `devel`; package identity/license set; scaffolding provenance preserved. |
| ST-011 | M0: Dune/opam/devcontainer/CI skeleton | Planned | ST-010 | Green build/test/format on OCaml 4.14 and pinned 5.x; sshd present; generated files pristine; no application dependency. |
| ST-012 | M0: Pin and characterize upstream oracle | Planned | ST-011 | Wheel/version/hash lock; executed minimal probes for whitespace, duplicates, unknown fields, integer syntax, empties; recorded compatibility table. |
| ST-020 | M1: Jsont exact-number/duplicate/limits proof | Planned | ST-011, ST-012 | Original token extraction above 2^53; all decoded duplicates detected; bounded malformed nesting; minimum supported dependency versions demonstrated in CI. |
| ST-021 | M1: Public dtype/index/error interfaces | Planned | ST-020 | Immutable index, all 13 dtypes, deterministic enumeration, structured errors, documented limits; API checks compile. |
| ST-022 | M1: Complete header/layout validation | Planned | ST-021 | Prefix/header checks, exact integers, checked sizes, no gaps/overlaps/trailing payload; scalar/empty boundary fixtures pass. |
| ST-023 | M1: Malformed input and resource regressions | Planned | ST-022 | Duplicate/Unicode/UTF-8/schema/overflow cases, early allocation limits, no leaked parser exceptions; bounded stress evidence. |
| ST-030 | M2: Memory reader | Planned | ST-022 | Full validation before reads; exact independent copies; oversize/missing/empty behavior tested. |
| ST-031 | M2: Unix reader and handle lifecycle | Planned | ST-030 | Same-descriptor reads, short-read/EINTR handling, truncation, bounded copies, bad ranges, idempotent close, no descriptor leaks. |
| ST-032 | M2: Test executable and access-path parity | Planned | ST-031 | Index + raw extraction interface; memory/copy/chunked agreement; no payload copy at open; no alignment assumptions. |
| ST-040 | M3: Offline synthetic corpus and generator | Planned | ST-012, ST-021 | All dtype/shape/metadata edge cases; under 1 MiB binary fixture budget; independent provenance and hand-calculated goldens; no network for `dune runtest`. |
| ST-041 | M3: Framework-free differential harness | Planned | ST-032, ST-040 | `deserialize` oracle; compare every name/dtype/shape/byte sequence and metadata; explicit acceptance-difference table; synthetic CI green. |
| ST-042 | M3: Locked HF fetch/cache tooling | Planned | ST-011, ST-003 | Anonymous immutable URLs; per-file/total cap; fresh/cache hash checks; atomic files; clear timeout/unavailable failure; no silent skip. |
| ST-043 | M3: Execute full HF conformance | Planned | ST-041, ST-042 | Six files, 307 tensors; all bytes/metadata agree across access paths; lock digest + reference/reader versions in CI artifact. |
| ST-044 | M3: Properties and bounded fuzz replay | Planned | ST-023, ST-041 | Seeded 1,000-case PR suite; 10,000-case scheduled target; scalar/zero shapes included; saved/shrunk failures; subprocess limits for stress. |
| ST-050 | M4: Independent package install smoke tests | Planned | ST-032, ST-040 | Source tarball → clean opam switch → external Dune client; core works without Unix; file package independently installed; runtime works offline without Python/Rust/consumer repos. |
| ST-051 | M4: Documentation and support matrix | Planned | ST-043, ST-044, ST-050 | API examples, exactness, dtype subset, limits, ownership, file mutation assumptions, tested compiler/platform list; no unsupported portability claims. |
| ST-052 | M4: Release readiness and promotion | Planned | ST-011, ST-043, ST-044, ST-050, ST-051 | Same reader commit green across required jobs; no unreviewed oracle differences; clean logical commits; `devel` promoted only after evidence; registry updated. |

## Milestone gates

| Gate | Status | Required tasks |
| --- | --- | --- |
| M0 — Standalone skeleton and reference contract | Not started | ST-010–012 |
| M1 — Exact, bounded Jsont header/index | Not started | ST-020–023 |
| M2 — Memory and Unix bytes | Not started | ST-030–032 |
| M3 — Independent conformance | Not started | ST-040–044 |
| M4 — Standalone release readiness | Not started | ST-050–052 |

Critical sequence: bootstrap → reference probes → Jsont proof → index validation
→ memory/Unix readers → differential conformance → release readiness.
Fixture-fetch tooling and synthetic generation can proceed once their individual
dependencies are met. This does not require parallel agents.

## Decisions and remaining gates

| ID | Decision / uncertainty | Resolution |
| --- | --- | --- |
| D-01 | Name | Recommend `TheCBaH/ocaml-safetensors`; recheck at ST-010, not reserved. |
| D-02 | Consumer scope | Exclude all `mltorch` and producer-sidecar implementation and testing. |
| D-03 | Reference | Pin 0.8.0 initially; resolve wheel hashes and execute probes in ST-012. |
| D-04 | Whitespace | Accept JSON whitespace around the root object, matching the released reader. |
| D-05 | Jsont exact integers and limits | Required proof in ST-020; no lossy fallback. |
| D-06 | Duplicate/unknown-field differences | OCaml rejects; characterize upstream in ST-012 and retain explicit differences. |
| D-07 | HF corpus | Six files under 5 MiB suite / 2 MiB each; raw headers verified, reader comparisons still pending. |
| D-08 | Offline fixtures | Synthetic project-owned binaries in Git; HF payloads fetched separately, not redistributed in package. |
| D-09 | Package independence | No Python/Rust/tensor framework at runtime; oracle remains test-only. |

## Execution evidence log

Only completed research is recorded so far:

| Date | IDs | Evidence | Limit |
| --- | --- | --- | --- |
| 2026-09-29 | ST-001–005 | Plan, design amendments, verification report, fixture lock; full-file hashes and header summaries checked during research. | No library implementation, target build, upstream runtime test, or CI run. |

For each future task, append: date, task ID, owner, branch/commit, CI URL,
fixture-lock digest where relevant, outcome, and next action. Store large logs
as workflow artifacts and link them here. A release entry must identify the
exact source commit and all required passing jobs.
