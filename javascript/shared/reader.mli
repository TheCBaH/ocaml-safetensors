val of_uint8array :
  ?limits:Safetensors.Limits.t ->
  Byte_buffer.t ->
  (Safetensors.Memory.t, Safetensors.Error.t) result
(** Copy an attached, unshared Uint8Array view, then validate its contents. Node
    Buffer views are accepted. Offsets are relative to the supplied view. *)

val copy_tensor :
  Safetensors.Memory.t -> string -> (Byte_buffer.t, Safetensors.Error.t) result
(** Return a fresh Uint8Array containing the tensor's raw bytes. *)
