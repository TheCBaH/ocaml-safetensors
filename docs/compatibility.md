# Reference compatibility

Reference: Python safetensors 0.8.0, using its Rust-backed raw `deserialize`
API. These probes were executed locally on 2026-10-01 and are repeated in CI.
The test asserts every expected outcome; changes require explicit review.

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
| `integer-string` | no | no | invalid_json |
| `large-exact` | yes | yes | — |
| `unsigned-dimension` | yes | no | resource_limit / signed int64 implementation limit |
| `empty-product-overflow` | no | yes | zero dimensions recognized before multiplication |
| `unsupported-fp8` | yes | no | unsupported_dtype / declared dtype subset |
| `metadata-type` | no | no | invalid_json |
| `trailing-data` | no | no | size_mismatch |
| `short-prefix` | no | no | truncated |
| `huge-prefix` | no | no | resource_limit |
| `shape-size` | no | no | size_mismatch |
| `overlap` | no | no | invalid_offsets |
| `gap` | no | no | invalid_offsets |
| `deep-nesting` | no | no | invalid_json |
| `bounded-rank` | yes | no | resource_limit / configured rank limit |

The OCaml reader rejects duplicate decoded member names even where the reference
keeps the last value. It rejects unknown tensor fields and types outside its
declared subset. Shape/offset values are limited to signed int64 and configured
resource budgets. For empty tensors it detects zero dimensions before
multiplication, avoiding overflow from dimensions whose product is immaterial.

The reference's positive structural validation does not authenticate a file or
scan numerical values. The conformance harness separately compares raw bytes
and verifies external fixture hashes. It does not deserialize pickle or run
model code. See [the harness](../scripts/conformance.py) for exact probe inputs.
