# Reference compatibility

Reference: Python safetensors 0.8.0, using its Rust-backed raw `deserialize`
API. The table records expectations asserted by the conformance harness;
current execution evidence is written to `.cache/reports/synthetic.json` and
CI logs. Changes require explicit review.

| Input | Reference accepts | OCaml accepts | OCaml error / deliberate difference |
| --- | --- | --- | --- |
| `whitespace` | yes | yes | — |
| `empty` | yes | yes | — |
| `scalar` | yes | yes | — |
| `zero-shape` | yes | yes | — |
| `duplicate-root` | yes | no | duplicate_member / strict duplicate policy |
| `escaped-duplicate` | yes | no | duplicate_member / strict duplicate policy |
| `duplicate-metadata` | yes | no | duplicate_member / strict duplicate policy |
| `duplicate-field` | no | no | duplicate_member |
| `unknown-field` | yes | no | invalid_header / strict unknown-field policy |
| `fraction` | no | no | invalid_integer |
| `exponent` | no | no | invalid_integer |
| `negative-zero` | no | no | invalid_integer |
| `integer-string` | no | no | invalid_header |
| `large-exact` | yes | yes | — |
| `unsigned-dimension` | yes | no | invalid_integer / signed int64 implementation limit |
| `empty-product-overflow` | no | yes | zero dimensions recognized before multiplication |
| `supported-fp8` | yes | yes | — |
| `dtype-F8_E5M2`, `dtype-F8_E4M3`, `dtype-F8_E8M0` | yes | yes | Raw bytes preserved |
| `dtype-F8_E4M3FNUZ`, `dtype-F8_E5M2FNUZ`, `dtype-C64` | yes | yes | Raw bytes preserved |
| `mixed-fp8-f32` | yes | yes | — |
| `metadata-type` | no | no | invalid_header |
| `trailing-data` | no | no | size_mismatch |
| `short-prefix` | no | no | truncated |
| `huge-prefix` | no | no | invalid_integer / unsigned length exceeds signed int64 |
| `shape-size` | no | no | size_mismatch |
| `overlap` | no | no | invalid_offsets |
| `gap` | no | no | invalid_offsets |
| `deep-nesting` | no | no | invalid_header / unexpected nested value sort |
| `bounded-rank` | yes | no | resource_limit / configured rank limit |

The OCaml reader rejects duplicate decoded member names even where the reference
keeps the last value. It rejects unknown tensor fields and types outside its
declared subset: 19 of the reference's 22 storage types, with packed `F4`,
`F6_E2M3` and `F6_E3M2` deferred. Shape/offset values are limited to signed
int64 and configured resource budgets. For empty tensors it validates every
dimension and detects zero dimensions before
multiplication, avoiding overflow from dimensions whose product is immaterial.

Syntax and UTF-8 failures use `invalid_json`; wrong schema sorts use
`invalid_header`. Invalid integer tokens, signed-int64 overflow and tensor
arithmetic overflow use `invalid_integer`; configured budgets and hard
allocation limits use `resource_limit`. Specific dtype, duplicate, offset and
size errors retain their own kinds. A wrong sort can be rejected before the
remainder of its value is parsed, so an input with several defects has no
universal syntax-first precedence. Error paths use JSON string escaping and
byte offsets are absolute file offsets. Messages are presentation text and
can vary with Jsont versions.

Seeded differential cases include valid files, arbitrary bytes, prefix-aware
byte changes and targeted number/schema mutations. The policy allowlist
checks the actual rejecting field and structural difference: duplicate root
or metadata keys, unknown tensor fields, deferred packed dtypes, signed-int64
dimensions, rank limits and zero-dimension intermediate-overflow behavior.
It does not excuse arbitrary malformed-file disagreements. When both readers
accept, names, metadata, descriptors and every tensor byte must agree.

The reference's positive structural validation does not authenticate a file or
scan numerical values. The conformance harness separately compares raw bytes
and verifies external fixture hashes. It does not deserialize pickle or run
model code. See [the harness](../scripts/conformance.py) for exact probe inputs.
