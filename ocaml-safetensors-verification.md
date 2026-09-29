# Safetensors verification research

Inspected: 2026-09-29. Scope: standalone OCaml reader; no `mltorch` integration.
This is source inspection and fixture discovery, not a completed reader test run.
See the [implementation plan](ocaml-safetensors-plan.md),
[tracker](ocaml-safetensors-tracker.md), and
[fixture lock](ocaml-safetensors-fixtures.json).

## Upstream baseline

Use release **0.8.0**, commit
`a406ca3e7a90598be0cd05a50069cb9bf5ef6ba6`, as the initial reference oracle.
The GitHub latest-release endpoint identified this release during research.
Also inspected `main` at `e246a2560645b7525f5775669ed816eb57c5bcc8`
(`0.9.0-dev.0`). Pin wheel hashes and Python version when implementing the
oracle; do not let an unpinned `pip install -U` change conformance expectations.
[Release](https://github.com/safetensors/safetensors/releases/tag/v0.8.0).

### What the reader validates

`SafeTensors::read_metadata` checks the length prefix, a 100,000,000-byte header
ceiling, header bounds, UTF-8, JSON, and complete buffer coverage.
`Metadata::validate` checks sorted contiguous offsets, checked shape/bit-size
multiplication, byte divisibility, and agreement with each tensor's byte span.
It does not authenticate weights or compare numerical values.
[Release reader](https://github.com/safetensors/safetensors/blob/a406ca3e7a90598be0cd05a50069cb9bf5ef6ba6/safetensors/src/tensor.rs#L390).

The release has explicit tests accepting leading and trailing JSON whitespace.
The older README wording requiring the first byte to be `{` and mentioning
space-only padding is narrower. Adopt the released reader's whitespace behavior.
Top-level tensors and user metadata are deserialized into hash maps, so duplicate
handling needs characterization; do not infer strict rejection from the format
prose. [Validation and tests](https://github.com/safetensors/safetensors/blob/a406ca3e7a90598be0cd05a50069cb9bf5ef6ba6/safetensors/src/tensor.rs#L1534).

### How upstream tests it

| Layer | Inspected evidence | Application to this project |
| --- | --- | --- |
| Rust core | Unit cases cover truncation, malformed metadata, overlap, overflow, empties, serialization, and slicing. Proptest checks indexing and round trips with 20 cases; its shape generator excludes scalars and zero dimensions. `test_gpt2*` builds synthetic data, not downloaded checkpoints. | Port the relevant behaviors, add scalar/empty property cases, keep generated data small. An OCaml writer is unnecessary. |
| Python bindings | `test_simple.py` compares exact serialized bytes, NumPy values, metadata, ordering, and slicing. | Compare raw tensor bytes and metadata from an independent implementation. |
| Framework adapters | `test_pt_comparison.py` covers dtype behavior, devices, slices, and non-contiguous/shared tensors. | Borrow raw dtype/byte cases; GPU execution, alias reconstruction, and serializer restrictions are outside this reader's scope. |
| File backends | `test_pread_backend.py` includes truncated header/data, offset overflow, ownership, and backend tests. | Exercise seek/read and close behavior; don't assume memory-reader tests cover I/O. |
| Fuzzing | Rust libFuzzer passes arbitrary bytes to `SafeTensors::deserialize`; Python's Atheris harness calls Torch `load_file` on temporary files and catches exceptions. | Add bounded parser fuzzing and save minimized regressions; no Torch requirement for OCaml fuzz tests. |
| CI | Rust tests/clippy/audit across Linux, Windows, macOS, including no-std; Python framework matrices and an emulated s390x big-endian job. | Start with declared OCaml platforms and exact byte tests. Broader upstream coverage is evidence to learn from, not a requirement to duplicate every framework. |

Sources: [Rust property tests](https://github.com/safetensors/safetensors/blob/e246a2560645b7525f5775669ed816eb57c5bcc8/safetensors/src/tensor.rs#L945),
[Python basic tests](https://github.com/safetensors/safetensors/blob/e246a2560645b7525f5775669ed816eb57c5bcc8/bindings/python/tests/test_simple.py),
[Torch comparisons](https://github.com/safetensors/safetensors/blob/e246a2560645b7525f5775669ed816eb57c5bcc8/bindings/python/tests/test_pt_comparison.py),
[file backend tests](https://github.com/safetensors/safetensors/blob/e246a2560645b7525f5775669ed816eb57c5bcc8/bindings/python/tests/test_pread_backend.py),
[Rust fuzz target](https://github.com/safetensors/safetensors/blob/e246a2560645b7525f5775669ed816eb57c5bcc8/safetensors/fuzz/fuzz_targets/fuzz_target_1.rs),
[Python fuzz harness](https://github.com/safetensors/safetensors/blob/e246a2560645b7525f5775669ed816eb57c5bcc8/bindings/python/fuzz.py),
[Rust CI](https://github.com/safetensors/safetensors/blob/e246a2560645b7525f5775669ed816eb57c5bcc8/.github/workflows/rust.yml),
[Python CI](https://github.com/safetensors/safetensors/blob/e246a2560645b7525f5775669ed816eb57c5bcc8/.github/workflows/python.yml).

The presence of fuzz harnesses does not establish that the inspected PR
workflows continuously run them. The historical `attacks/` directory illustrates
failure modes, including overlapping ranges and allocation abuse; it is not a
corpus to run blindly in CI. Recreate bounded regression cases instead.
[Attack notes](https://github.com/safetensors/safetensors/blob/e246a2560645b7525f5775669ed816eb57c5bcc8/attacks/README.md).

### A framework-free oracle is available

The Python extension exports `safetensors.deserialize(bytes)`. It invokes the
Rust reader and returns each tensor's name, dtype string, shape, and raw
`bytearray`, including BF16 without requiring a NumPy BF16 conversion. This is
the primary differential oracle: neither Torch nor Transformers is needed.
Use `safe_open(..., framework="np").metadata()` for optional user metadata in
the oracle job; NumPy is a test-only dependency. Do not call `get_tensor` through
NumPy for unsupported numerical representations.
[Release binding](https://github.com/safetensors/safetensors/blob/a406ca3e7a90598be0cd05a50069cb9bf5ef6ba6/bindings/python/src/lib.rs#L278).

For each fixture, generate canonical reference JSON sorted by tensor name:
`name`, `dtype`, exact integer `shape`, byte length, and SHA-256 of the raw bytes;
record optional metadata separately. Derive these expected values from the
reference API, never from the OCaml reader. Compare every tensor, not a sample.
For tiny synthetic inputs, compare byte arrays directly as well. Offsets and
header boundaries additionally need hand-calculated golden cases, because the
reference's public `deserialize` result does not expose offsets.

For successful input, compare memory, file-copy, and chunked-read results to
that oracle. For rejected input, compare acceptance and broad error categories,
not unstable exception text. Maintain an explicit difference table for duplicate
keys, unknown fields, integer syntax/range, policy limits, and unsupported dtypes.
Where upstream is permissive, a documented stricter OCaml policy can be valid;
a new unexplained difference fails the conformance job. No upstream execution
has been performed during this planning task.

## Selected Hugging Face corpus

All six files were fetched anonymously at the listed immutable revisions.
Actual file sizes and SHA-256 hashes were checked, and headers inspected with
Python's JSON decoder solely for discovery. The committed JSON lock contains
full revisions, pinned download URLs, hashes, header/payload sizes, tensor
counts, dtype counts, metadata, and representative names. The research downloads
are temporary; no checkpoint binaries are added to this workspace's deliverables.

Total: **3,114,833 bytes (2.97 MiB)**, of which 3,081,652 bytes are payload;
**307 tensors**. Each file is below 1.11 MB. The proposed fetcher caps each file
at 2 MiB and the complete set at 5 MiB, including cached entries. This is enough
to exercise real producer layouts without large model downloads or inference.

| ID and pinned source | File bytes | Payload bytes | Actual coverage |
| --- | ---: | ---: | --- |
| `clip-shard`: [tiny diffusion text encoder, shard 1](https://huggingface.co/hf-internal-testing/tiny-stable-diffusion-pipe-indexes/blob/cf7fc42704b27a998192df2d95fea37ff2792a18/text_encoder/model-00001-of-00004.safetensors) | 750 | 616 | 1 I64 tensor, shape `[1,77]`; payload starts at byte 134. Read as one ordinary file; no shard-index resolver. |
| `vit`: [tiny-random-vit](https://huggingface.co/hf-internal-testing/tiny-random-vit/blob/96e253fe90cfcededfa8edf8b7e6f230f87a63a1/model.safetensors) | 176,460 | 167,020 | 88 F32 tensors; ranks 1–4, including image projection weights. |
| `clip-unaligned`: [tiny diffusion text encoder](https://huggingface.co/hf-internal-testing/tiny-stable-diffusion-pipe-safetensors/blob/1d6dee47dabc49f0b52d9b1c7a3b6bef244360cb/text_encoder/model.safetensors) | 283,923 | 274,508 | 84 F32 + 1 I64; payload starts at byte 9,415, deliberately exercising unaligned file access. |
| `bert`: [tiny-random-bert](https://huggingface.co/hf-internal-testing/tiny-random-bert/blob/f171d7baecaf37b5da5a3616d8833b9969753535/model.safetensors) | 520,212 | 509,452 | 99 F32 + 1 I64; 100 named tensors and alias-related string metadata. Metadata must remain uninterpreted. |
| `llama-f16`: [llama-2-tiny-random](https://huggingface.co/yujiepan/llama-2-tiny-random/blob/74bb065d6381fdf9fcde5896cb32267ba2c0ee0a/model.safetensors) | 1,027,424 | 1,026,104 | 12 F16 + 1 F32; mixed float widths in one checkpoint. |
| `baguettotron-bf16`: [baguettotron-tiny-random](https://huggingface.co/yujiepan/baguettotron-tiny-random/blob/af0b4761164785c04017e74bed9a6a13fdf2d44d/model.safetensors) | 1,106,064 | 1,103,952 | 20 BF16 tensors; raw-bit verification without numerical conversion. |

These are representative of storage layouts and dtype access, not model quality
or the entire safetensors ecosystem. None of the six contains scalar or empty
tensors. Synthetic fixtures must cover those, remaining supported integer/boolean
and F64 types, special float bit patterns, unusual names, malformed inputs, and
large integer boundaries. The corpus does not establish support for FP8, complex,
packed sub-byte data, or sharded model assembly.

The Hub API reports Apache-2.0 for `clip-unaligned`; it does not declare a license
for the other selected models. Keep links/hashes in Git and fetch fixtures for
tests; do not redistribute these checkpoint binaries as package contents. A
missing license field is recorded as unknown, not inferred from a parent model.
Use synthetic project-owned fixtures for offline package tests.

### Candidates deliberately excluded

- `hf-internal-testing/tiny-stable-diffusion-pipe-indexes`'s
  `safety_checker/model.fp16.safetensors` actually contains 92 F32 tensors and
  one I64. Its hash matches the ordinary filename. It adds no F16 coverage.
- `hf-internal-testing/tiny-random-gpt2` is usable (453,864 bytes; 64 F32
  tensors, SHA-256 `8111d5afb0715dbf5a31396d31432cb56370ba23f6650a035ea0fc8a20b4e500`),
  but redundant for this initial budget.
- The inspected `tiny-random-resnet`, `tiny-random-bart-fp16`, and
  `tiny-stable-diffusion-xl-pipe` repositories have no `.safetensors` file.
  A model name or advertised numerical precision is insufficient evidence.
- The existing producer's RepViT checkpoint is about 29.5 MB; standalone
  conformance does not need that larger consumer-specific dependency.

## Fetching and evidence rules

The eventual fetch command reads only the lock, uses immutable URLs, requires
no HF token, checks size/hash on cache hits as well as fresh files, downloads to
a temporary path, and renames only after verification. It enforces byte caps
while downloading, timeouts, bounded retries, and reports inaccessible fixtures
as infrastructure failures rather than quietly skipping them. It never loads
model code, tokenizers, pickle, or `trust_remote_code`.

The Hub suite is a separate required release check. Offline unit/package tests
must still run with network access disabled and no Hub cache. An unavailable
remote blocks Hub conformance evidence, not the ability to run local tests.
Store the fixture-lock digest, reader commit, reference version/wheel hash,
platform, test seed, per-file results, and discrepancy report as CI artifacts.
No release is declared verified from this research lock alone.
