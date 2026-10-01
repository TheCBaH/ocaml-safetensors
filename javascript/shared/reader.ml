let of_uint8array ?limits view =
  let n = Byte_buffer.length view in
  if n < 0 then
    Error
      (Safetensors.Error.make Safetensors.Error.Invalid_argument
         "expected an attached, unshared Uint8Array")
  else if n > min Sys.max_string_length 0x3fffffff then
    Error
      (Safetensors.Error.make Safetensors.Error.Resource_limit
         "byte buffer exceeds target copy limit")
  else
    let data = String.init n (fun i -> Char.chr (Byte_buffer.get view i)) in
    Safetensors.Memory.of_string ?limits data

let copy_tensor reader name =
  match Safetensors.Memory.copy_tensor reader name with
  | Error e -> Error e
  | Ok bytes ->
      let view = Byte_buffer.create (Bytes.length bytes) in
      Bytes.iteri (fun i c -> Byte_buffer.set view i (Char.code c)) bytes;
      Ok view
