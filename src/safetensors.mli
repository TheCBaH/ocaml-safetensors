(** A standalone reader for safetensors metadata and little-endian tensor bytes.
    No numerical conversion or tensor framework is involved. *)

module Error : sig
  (** Machine-readable failures shared by core, Unix and adapter APIs.
      [Invalid_json] denotes syntax or UTF-8 errors; [Invalid_header] denotes
      wrong schema sorts; [Invalid_integer] includes token/range/arithmetic
      errors; [Resource_limit] denotes a budget or hard allocation limit. Inputs
      with multiple defects have no syntax-first precedence guarantee. *)
  type kind =
    | Io
    | Truncated
    | Invalid_header
    | Invalid_json
    | Duplicate_member
    | Invalid_integer
    | Unsupported_dtype
    | Invalid_offsets
    | Size_mismatch
    | Resource_limit
    | Missing_tensor
    | Closed
    | Invalid_argument

  type t
  (** Structured failure with optional context. *)

  val make :
    ?tensor:string -> ?byte_offset:int64 -> ?path:string -> kind -> string -> t
  (** Construct a failure. [byte_offset] is an absolute file-byte offset; [path]
      is a JSON member/index path, when applicable. *)

  val kind : t -> kind
  (** Stable failure category. *)

  val message : t -> string
  (** Human-readable presentation text; upstream diagnostics can vary with
      dependency versions. Match {!kind} rather than this text. *)

  val tensor : t -> string option
  (** Affected decoded tensor name, when known. *)

  val byte_offset : t -> int64 option
  (** Available absolute file-byte location, including the eight-byte prefix. *)

  val path : t -> string option
  (** Compatibility name for {!json_path}. *)

  val json_path : t -> string option
  (** JSON-escaped member/index path rooted at [$], when available. *)

  val kind_name : kind -> string
  (** Stable lowercase name of a category. *)

  val pp : Format.formatter -> t -> unit
  (** Format the category, message and available context for presentation. *)
end

module Limits : sig
  type t
  (** Nonnegative decoding budgets. The strict schema bounds nesting itself;
      there is no configurable depth limit. *)

  val default : t
  (** 100,000,000 header bytes, 100,000 tensors, rank 64, 4,096 bytes per
      decoded member name and 100,000 user-metadata entries. *)

  val make :
    ?max_header_bytes:int ->
    ?max_tensors:int ->
    ?max_rank:int ->
    ?max_name_bytes:int ->
    ?max_metadata_entries:int ->
    unit ->
    (t, Error.t) result
  (** Override defaults. Zero is permitted. Negative budgets and
      [max_tensors = max_int] return [Invalid_argument]. Counts bound decoding;
      the header cap also bounds individual strings. A decoded header may use
      several times its encoded size in memory. *)

  val max_header_bytes : t -> int
  (** Maximum encoded header size, excluding the eight-byte prefix. *)

  val max_tensors : t -> int
  (** Maximum tensor count, excluding the reserved metadata object. *)

  val max_rank : t -> int
  (** Maximum dimensions per tensor; a scalar has rank zero. *)

  val max_name_bytes : t -> int
  (** Maximum UTF-8 bytes per decoded JSON member name at every schema level. *)

  val max_metadata_entries : t -> int
  (** Maximum string pairs in the reserved metadata object. *)
end

module Dtype : sig
  type t =
    | Bool
    | U8
    | I8
    | U16
    | I16
    | U32
    | I32
    | U64
    | I64
    | F16
    | BF16
    | F32
    | F64
    | F8_E5M2
    | F8_E4M3
    | F8_E8M0
    | F8_E4M3FNUZ
    | F8_E5M2FNUZ
    | C64

  val of_string : string -> (t, Error.t) result
  (** Parse an exact safetensors storage-type name, or return
      [Unsupported_dtype]. Packed F4/F6 types are not supported. *)

  val to_string : t -> string
  (** Canonical safetensors name. *)

  val byte_width : t -> int
  (** Storage bytes per element; no numerical conversion is implied. *)
end

module Tensor : sig
  type t
  (** Validated descriptor. Offsets are relative to the payload, not the file.
  *)

  val name : t -> string
  (** Decoded UTF-8 tensor name. *)

  val dtype : t -> Dtype.t
  (** Raw storage type. *)

  val shape : t -> int64 list
  (** Nonnegative dimensions in C-order; the empty list denotes a scalar. *)

  val data_offsets : t -> int64 * int64
  (** Inclusive start and exclusive end within the payload. *)

  val byte_length : t -> int64
  (** Validated difference between the two data offsets. *)
end

module Index : sig
  type t
  (** Complete validated metadata and descriptor index. All ranges are checked
      for size, bounds, contiguity and full payload coverage before success. *)

  val header_length :
    ?limits:Limits.t -> file_size:int64 -> string -> (int, Error.t) result
  (** Validate an exactly eight-byte little-endian prefix against [file_size]
      and header/allocation budgets before allocating the header. Returns its
      encoded length, excluding the prefix. *)

  val decode_header :
    ?limits:Limits.t -> file_size:int64 -> string -> (t, Error.t) result
  (** Decode only the header string against the supplied complete [file_size].
      Duplicate decoded names, unknown tensor fields and unsupported types are
      errors. Integers are read exactly from decimal tokens without a lossy
      float conversion. No payload availability or snapshot is established. *)

  val metadata : t -> (string * string) list
  (** String metadata in deterministic bytewise key order. *)

  val tensors : t -> Tensor.t list
  (** Deterministic bytewise name order. *)

  val find : t -> string -> Tensor.t option
  (** Find a descriptor by its exact decoded name. *)

  val data_start : t -> int64
  (** Absolute file offset immediately after the prefix and header. *)
end

module Bigstring : sig
  type t =
    (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
  (** The payload kind shared by [Unix.map_file], js_of_ocaml's
      [Typed_array.Bigstring] and the Melange bigarray shim. *)
end

module Memory : sig
  type t
  (** Validated reader retaining its complete backing storage. *)

  val of_string : ?limits:Limits.t -> string -> (t, Error.t) result
  (** Retains the immutable input. All descriptors are validated before success.
  *)

  val of_bigstring : ?limits:Limits.t -> Bigstring.t -> (t, Error.t) result
  (** Like {!of_string} over a retained bigstring. The payload is not copied;
      header decoding allocates. The caller must not mutate the backing array or
      its aliases while the reader or any tensor view is in use. *)

  val index : t -> Index.t
  (** The complete validated index, independent of later payload access. *)

  val copy_tensor : t -> string -> (bytes, Error.t) result
  (** Independent mutable copy. Missing names return [Missing_tensor]; copies
      above [Sys.max_string_length] return tensor-labelled [Resource_limit].
      Runtime memory exhaustion is not converted to a structured failure. *)

  val tensor_view : t -> string -> (Bigstring.t, Error.t) result
  (** Raw bytes: an alias with no payload copy for {!of_bigstring}, a fresh
      bigarray copy for {!of_string}. Missing names return [Missing_tensor]. An
      alias keeps the whole backing storage alive after the reader is dropped;
      it owns no independent bytes and must remain unmodified. *)
end
