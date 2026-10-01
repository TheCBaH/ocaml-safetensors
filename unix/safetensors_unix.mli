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

val close : t -> unit
(** Idempotent. Previously returned bytes and index values remain usable. *)

val with_file :
  ?limits:Safetensors.Limits.t ->
  string ->
  (t -> ('a, Safetensors.Error.t) result) ->
  ('a, Safetensors.Error.t) result
(** Closes the descriptor even if the callback raises. Callback exceptions are
    propagated; expected file and format errors are returned as results. *)
