(** A standalone reader for safetensors metadata and little-endian tensor bytes.
    No numerical conversion or tensor framework is involved. *)

module Error : sig
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

  val make :
    ?tensor:string -> ?byte_offset:int64 -> ?path:string -> kind -> string -> t

  val kind : t -> kind
  val message : t -> string
  val tensor : t -> string option
  val byte_offset : t -> int64 option
  val path : t -> string option
  val kind_name : kind -> string
  val pp : Format.formatter -> t -> unit
end

module Limits : sig
  type t

  val default : t

  val make :
    ?max_header_bytes:int ->
    ?max_tensors:int ->
    ?max_rank:int ->
    ?max_name_bytes:int ->
    ?max_metadata_entries:int ->
    ?max_depth:int ->
    unit ->
    (t, Error.t) result

  val max_header_bytes : t -> int
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

  val of_string : string -> (t, Error.t) result
  val to_string : t -> string
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

  val header_length :
    ?limits:Limits.t -> file_size:int64 -> string -> (int, Error.t) result
  (** Validate an exactly eight-byte prefix before allocating the header. *)

  val decode_header :
    ?limits:Limits.t -> file_size:int64 -> string -> (t, Error.t) result
  (** The string contains only the header. Its length is N. Validation uses the
      supplied complete file size; it does not establish payload availability.
  *)

  val metadata : t -> (string * string) list

  val tensors : t -> Tensor.t list
  (** Deterministic bytewise name order. *)

  val find : t -> string -> Tensor.t option
  val data_start : t -> int64
end

module Memory : sig
  type t

  val of_string : ?limits:Limits.t -> string -> (t, Error.t) result
  (** Retains the immutable input. All descriptors are validated before success.
  *)

  val index : t -> Index.t
  val copy_tensor : t -> string -> (bytes, Error.t) result
end
