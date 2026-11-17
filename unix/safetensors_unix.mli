type t
(** Copy-based Unix file access. A handle owns one descriptor and is not safe
    for concurrent operations. The file must remain unchanged while open. *)

val open_file :
  ?limits:Safetensors.Limits.t -> string -> (t, Safetensors.Error.t) result

val index : t -> Safetensors.Index.t
val copy_tensor : t -> string -> (bytes, Safetensors.Error.t) result

val read_into :
  t ->
  string ->
  tensor_offset:int64 ->
  bytes ->
  dst_off:int ->
  len:int ->
  (unit, Safetensors.Error.t) result
(** Read a bounded tensor slice into [dst]. An I/O error or EOF may leave a
    prefix of the requested destination modified. Bytes outside that slice are
    unchanged. An I/O/EOF [byte_offset] names the requested file-byte start, not
    the first unread byte. Operations on a handle must be serialized. *)

val close : t -> unit
(** Idempotent. Previously returned bytes and index values remain usable. *)

val with_file :
  ?limits:Safetensors.Limits.t ->
  string ->
  (t -> ('a, Safetensors.Error.t) result) ->
  ('a, Safetensors.Error.t) result
(** Closes the descriptor even if the callback raises. Callback exceptions are
    propagated; expected file and format errors are returned as results. *)

module Mmap : sig
  val open_file :
    ?limits:Safetensors.Limits.t ->
    string ->
    (Safetensors.Memory.t, Safetensors.Error.t) result
  (** Map the whole file privately with copy-on-write pages. Tensor views alias
      this mapping; writes are possible but forbidden by the reader contract and
      never update the file. The descriptor closes on return. The mapping lives
      until the reader and all views are collected; there is no explicit unmap.
      The file must remain unchanged while mapped: truncating it can cause a
      fatal SIGBUS when a mapped page is accessed. Neither this reader nor the
      descriptor reader provides a snapshot of a file that is concurrently
      rewritten. *)
end
