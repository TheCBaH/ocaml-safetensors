# Reader design

The reader validates an entire safetensors index before exposing any tensor.
It provides descriptors and raw little-endian bytes, without numerical
conversion, framework initialization or code execution. The portable core has
no Unix dependency; the separate Unix package adds descriptor and mmap access.

## Validation policy

The eight-byte prefix and header budget are checked before allocating the
header. Jsont decodes the fixed schema with source locations. Integer values
are recovered from their original decimal tokens, rather than from Jsont's
rounded floating-point value. Dimensions and offsets must fit nonnegative
signed int64; checked arithmetic prevents byte-count wraparound. Every
dimension is validated even when a zero makes the tensor empty.

Names are compared after JSON unescaping. Duplicate root names, metadata keys
and tensor fields are errors, including differently escaped spellings of the
same name. Rejecting ambiguity avoids disagreement between consumers about
which descriptor or metadata value is authoritative. Unknown tensor fields
are also rejected: accepted descriptors contain only `dtype`, `shape` and
`data_offsets`. Arbitrary tensor names and string-valued user metadata remain
supported. Strict value sorts bound nesting without a generic JSON tree or an
unknown-value traversal.

Every range must agree with its shape and dtype, lie inside the payload and
join the sorted ranges without overlap or gaps. The final range must cover
the entire payload. Sorting by both endpoints permits empty tensors at valid
boundaries. Header-only validation uses the caller's stated total file size;
it cannot establish that the payload is actually present or unchanged.

Default limits retain compatibility with large ordinary model headers while
bounding hostile input: 100,000,000 header bytes, 100,000 tensors, rank 64,
4,096 bytes per decoded member name and 100,000 metadata entries. These are
policy defaults, not a guarantee of memory availability. The header cap also
bounds individual string values; decoded structures can consume several times
the encoded size. Applications can lower each limit with `Limits.make` and
inspect the resulting settings through its getters. There is no configurable
`max_depth`: the accepted schema itself has at most three nested containers.
Member callbacks run after a member's value is decoded, so duplicate/name/count
checks do not imply rejection before decoding that value.

Syntax and invalid UTF-8 use `Invalid_json`; wrong schema sorts use
`Invalid_header`; invalid or unsupported integer tokens and arithmetic overflow
use `Invalid_integer`. Budget and hard allocation limits use `Resource_limit`.
Specific duplicate, dtype, offset and size kinds preserve the failing
invariant. The parser can reject a wrong sort before consuming its whole value,
so malformed inputs with several defects have no universal syntax-first
precedence. Kinds and available context are machine-readable; human messages
are not a stable serialization format. JSON paths use JSON string escaping,
and byte offsets are absolute offsets in the complete file, including its
eight-byte prefix. See [compatibility](compatibility.md) for oracle differences.

## Storage and lifetime

`Memory.of_string` retains immutable input; `Memory.of_bigstring` borrows and
retains its backing array. A tensor view aliases bigstring storage and owns no
independent bytes; the string path instead allocates a fresh bigarray per
view. Both paths validate descriptors before returning the reader. An alias
keeps its backing storage alive after the reader is dropped. Callers must not
mutate borrowed storage or aliases while any reader or view is in use.
`copy_tensor` provides an independent mutable bytes value.

The descriptor reader owns a regular-file descriptor. Reads use seek followed
by read, so operations on one handle must be serialized. An error during
`read_into` can leave part of the requested destination range overwritten.
Closing the handle does not invalidate returned copies or index metadata.

The mmap reader closes its descriptor after creating a private writable
copy-on-write mapping. The interface presents it as immutable by contract;
bigarrays do not enforce that contract. A write can affect other aliases but
does not modify the source file. The GC releases the mapping only after the
reader and all views become unreachable; there is no explicit unmap API.

Both Unix readers require an unchanged file. Neither snapshots a concurrently
rewritten file. Mapped truncation can kill the process with `SIGBUS`; a
descriptor read can report EOF but cannot detect every rewrite beneath its
saved index. Publish immutable files or synchronize access before opening.
The owning JavaScript adapters deliberately copy Uint8Array input and tensor
output; their contract differs from the core's borrowed bigstring API. Both
js_of_ocaml and Melange adapters remain supported.

## Compatibility evidence and scope

The raw-byte oracle is Python safetensors 0.8.0's Rust-backed `deserialize`
API. Fixtures include independently generated binary cases and six small Hub
files selected during the 2026-09-29 investigation, bounded to 2 MiB per file
and 5 MiB total. The corpus covers small model layouts and metadata without
downloading full checkpoints. It is a compatibility sample, not an exhaustive
survey. The [fixture lock](../ocaml-safetensors-fixtures.json) records immutable
revisions, sizes, hashes and historical discovery flags. Its `executed: false`
values describe that investigation, not the latest tests. Current execution
evidence belongs in `.cache/reports/` and CI.

The supported storage types include the five byte-aligned FP8 variants and
`C64`; their bytes are never decoded or normalized. Packed `F4`, `F6_E2M3` and
`F6_E3M2` remain deferred because their sizing and alignment require a separate
width API decision. Writers, downloads, shard resolution, numerical casts,
typed tensor interpretation, GPU access and framework integration remain
consumer responsibilities. The Melange Jsont patch remains local to the
optional build; extracting a shared patched dependency is a separate package
effort. Borrowed JavaScript adapters, split copy/view entry points and copy-loop
optimizations need demonstrated consumer demand or measurements.
