open Safetensors

let get = function
  | Ok x -> x
  | Error e -> failwith (Format.asprintf "%a" Error.pp e)

let file header payload =
  let prefix = Bytes.create 8 in
  Bytes.set_int64_le prefix 0 (Int64.of_int (String.length header));
  Bytes.to_string prefix ^ header ^ payload

let () =
  let h = {|{"x":{"dtype":"I32","shape":[1],"data_offsets":[0,4]}}|} in
  let t = get (Memory.of_string (file h "\001\000\000\000")) in
  assert (get (Memory.copy_tensor t "x") = Bytes.of_string "\001\000\000\000");
  let huge =
    {|{"é":{"dtype":"U8","shape":[9007199254740993,0],"data_offsets":[0,0]}}|}
  in
  let t = get (Memory.of_string (file huge "")) in
  let tensor = Option.get (Index.find (Memory.index t) "é") in
  assert (Tensor.shape tensor = [ 9007199254740993L; 0L ]);
  let dup =
    {|{"x":{"dtype":"U8","dtype":"U8","shape":[0],"data_offsets":[0,0]}}|}
  in
  (match Memory.of_string (file dup "") with
  | Error e -> assert (Error.kind e = Error.Duplicate_member)
  | Ok _ -> failwith "duplicate accepted");
  print_endline "parser proof: exact tokens, duplicate fields, memory bytes"
