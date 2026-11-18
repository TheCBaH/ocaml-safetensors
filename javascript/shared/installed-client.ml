let () =
  let limits =
    Result.get_ok
      (Safetensors.Limits.make ~max_header_bytes:256 ~max_tensors:2 ~max_rank:3
         ~max_name_bytes:32 ~max_metadata_entries:4 ())
  in
  assert (Safetensors.Limits.max_header_bytes limits = 256);
  assert (Safetensors.Limits.max_tensors limits = 2);
  assert (Safetensors.Limits.max_rank limits = 3);
  assert (Safetensors.Limits.max_name_bytes limits = 32);
  assert (Safetensors.Limits.max_metadata_entries limits = 4);
  assert (Safetensors.Dtype.of_string "F8_E5M2" = Ok Safetensors.Dtype.F8_E5M2);
  assert (Safetensors.Dtype.byte_width Safetensors.Dtype.C64 = 8);
  let error =
    Safetensors.Error.make ~path:"$[\"x\"]" Safetensors.Error.Invalid_header
      "example"
  in
  assert (Safetensors.Error.json_path error = Safetensors.Error.path error);
  let header = {|{"x":{"dtype":"U8","shape":[1],"data_offsets":[0,1]}}|} in
  let prefix = Bytes.make 8 '\000' in
  Bytes.set_int64_le prefix 0 (Int64.of_int (String.length header));
  let data = Bytes.to_string prefix ^ header ^ "A" in
  let input = Adapter.Byte_buffer.create (String.length data) in
  String.iteri (fun i c -> Adapter.Byte_buffer.set input i (Char.code c)) data;
  let reader = Result.get_ok (Adapter.Reader.of_uint8array input) in
  Adapter.Byte_buffer.set input (String.length data - 1) 0;
  let view = Result.get_ok (Safetensors.Memory.tensor_view reader "x") in
  assert (Bigarray.Array1.get view 0 = 'A');
  let output = Result.get_ok (Adapter.Reader.copy_tensor reader "x") in
  assert (Adapter.Byte_buffer.get output 0 = Char.code 'A');
  Adapter.Byte_buffer.set output 0 0;
  assert (Safetensors.Memory.copy_tensor reader "x" = Ok (Bytes.of_string "A"));
  assert (Result.is_error (Safetensors.Memory.tensor_view reader "missing"))
