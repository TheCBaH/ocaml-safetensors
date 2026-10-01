[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Safetensors

let get = function
  | Ok x -> x
  | Error e -> failwith (Format.asprintf "%a" Error.pp e)

let file h data =
  let p = Bytes.create 8 in
  Bytes.set_int64_le p 0 (Int64.of_int (String.length h));
  Bytes.to_string p ^ h ^ data

let desc ?(dtype = "U8") ?(shape = "[0]") ?(offsets = "[0,0]") () =
  Printf.sprintf {|{"dtype":%S,"shape":%s,"data_offsets":%s}|} dtype shape
    offsets

let header d = {|{"x":|} ^ d ^ "}"

let reject ?limits label kind bytes =
  match Memory.of_string ?limits bytes with
  | Ok _ -> failwith (label ^ ": accepted")
  | Error e ->
      if Error.kind e <> kind then
        failwith
          (Format.asprintf "%s: expected %s, got %a" label
             (Error.kind_name kind) Error.pp e)

let accepted h data = get (Memory.of_string (file h data))

let () =
  let dtype_sizes =
    [
      ("BOOL", 1);
      ("U8", 1);
      ("I8", 1);
      ("U16", 2);
      ("I16", 2);
      ("U32", 4);
      ("I32", 4);
      ("U64", 8);
      ("I64", 8);
      ("F16", 2);
      ("BF16", 2);
      ("F32", 4);
      ("F64", 8);
    ]
  in
  List.iter
    (fun (dtype, width) ->
      let bytes =
        String.init width (fun i -> Char.chr (((i * 71) + 128) mod 256))
      in
      let h =
        header
          (desc ~dtype ~shape:"[]" ~offsets:(Printf.sprintf "[0,%d]" width) ())
      in
      let r = accepted h bytes in
      let t = Option.get (Index.find (Memory.index r) "x") in
      assert (Dtype.byte_width (Tensor.dtype t) = width);
      assert (Tensor.shape t = []);
      let copy = get (Memory.copy_tensor r "x") in
      assert (Bytes.to_string copy = bytes);
      Bytes.fill copy 0 width '\000';
      assert (Bytes.to_string (get (Memory.copy_tensor r "x")) = bytes))
    dtype_sizes;
  List.iter
    (fun shape -> ignore (accepted (header (desc ~shape ())) ""))
    [
      "[0]";
      "[0,9223372036854775807,9223372036854775807]";
      "[9223372036854775807,9223372036854775807,0]";
      "[2,0,3]";
    ];
  let huge =
    {|{"é\u2603":{"dtype":"U8","shape":[9007199254740993,0],"data_offsets":[0,0]}}|}
  in
  let r = accepted huge "" in
  assert (
    Tensor.shape (Option.get (Index.find (Memory.index r) "é☃"))
    = [ 9007199254740993L; 0L ]);
  let r =
    accepted "\t\n{\"__metadata__\":{\"é\":\"值\",\"format\":\"pt\"}}\r \t\n" ""
  in
  assert (Index.metadata (Memory.index r) = [ ("format", "pt"); ("é", "值") ]);
  ignore (accepted "{}" "");
  let ordered =
    {|{"z":{"dtype":"U8","shape":[1],"data_offsets":[0,1]},"end":{"dtype":"U8","shape":[0],"data_offsets":[1,1]},"start":{"dtype":"U8","shape":[0],"data_offsets":[0,0]}}|}
  in
  let r = accepted ordered "a" in
  assert (
    List.map Tensor.name (Index.tensors (Memory.index r))
    = [ "end"; "start"; "z" ]);
  let tensor_json = desc () in
  let bad_headers =
    [
      ("syntax", "{", Error.Invalid_json);
      ("utf8", "{\"\255\":{}}", Error.Invalid_json);
      ("root-array", "[]", Error.Invalid_json);
      ("root-null", "null", Error.Invalid_json);
      ("trailing", "{}x", Error.Invalid_json);
      ("nul-padding", "{}\000", Error.Invalid_json);
      ("missing", {|{"x":{"dtype":"U8","shape":[0]}}|}, Error.Invalid_header);
      ( "unknown",
        {|{"x":{"dtype":"U8","shape":[0],"data_offsets":[0,0],"extra":"x"}}|},
        Error.Invalid_header );
      ("dtype", header (desc ~dtype:"F8_E4M3" ()), Error.Unsupported_dtype);
      ( "root-dup",
        "{\"x\":" ^ tensor_json ^ ",\"x\":" ^ tensor_json ^ "}",
        Error.Duplicate_member );
      ( "escaped-dup",
        "{\"x\":" ^ tensor_json ^ ",\"\\u0078\":" ^ tensor_json ^ "}",
        Error.Duplicate_member );
      ( "field-dup",
        {|{"x":{"dtype":"U8","dtype":"U8","shape":[0],"data_offsets":[0,0]}}|},
        Error.Duplicate_member );
      ( "shape-dup",
        {|{"x":{"dtype":"U8","shape":[0],"shape":[0],"data_offsets":[0,0]}}|},
        Error.Duplicate_member );
      ( "offset-dup",
        {|{"x":{"dtype":"U8","shape":[0],"data_offsets":[0,0],"data_offsets":[0,0]}}|},
        Error.Duplicate_member );
      ( "metadata-dup",
        {|{"__metadata__":{"a":"x","a":"y"}}|},
        Error.Duplicate_member );
      ( "reserved-dup",
        {|{"__metadata__":{},"__metadata__":{}}|},
        Error.Duplicate_member );
      ("metadata-value", {|{"__metadata__":{"a":[0]}}|}, Error.Invalid_header);
      ("metadata-null", {|{"__metadata__":null}|}, Error.Invalid_json);
      ("offset-length", header (desc ~offsets:"[0]" ()), Error.Invalid_offsets);
      ("negative", header (desc ~shape:"[-1]" ()), Error.Invalid_integer);
      ("negative-zero", header (desc ~shape:"[-0]" ()), Error.Invalid_integer);
      ("fraction", header (desc ~shape:"[0.0]" ()), Error.Invalid_integer);
      ( "rounded-fraction",
        header (desc ~shape:"[1.0000000000000000001]" ()),
        Error.Invalid_integer );
      ("exponent", header (desc ~shape:"[0e0]" ()), Error.Invalid_integer);
      ("string-integer", header (desc ~shape:"[\"0\"]" ()), Error.Invalid_json);
      ("null-integer", header (desc ~shape:"[null]" ()), Error.Invalid_integer);
      ( "overflow",
        header (desc ~shape:"[9223372036854775808,0]" ()),
        Error.Resource_limit );
      ( "multiplication",
        header (desc ~shape:"[9223372036854775807,2]" ()),
        Error.Resource_limit );
      ( "width-overflow",
        header (desc ~dtype:"F64" ~shape:"[9223372036854775807]" ()),
        Error.Resource_limit );
      ("mismatch", header (desc ~shape:"[1]" ()), Error.Size_mismatch);
      ("reverse", header (desc ~offsets:"[1,0]" ()), Error.Invalid_offsets);
      ("beyond", header (desc ~offsets:"[0,1]" ()), Error.Invalid_offsets);
      ("nested", {|{"x":{"shape":[[[[[[[[]]]]]]]]}}|}, Error.Invalid_json);
    ]
  in
  List.iter (fun (label, h, kind) -> reject label kind (file h "")) bad_headers;
  reject "short-prefix" Error.Truncated "1234567";
  reject "short-header" Error.Truncated (String.sub (file "{}" "") 0 9);
  reject "unsigned-prefix" Error.Resource_limit (String.make 8 '\255');
  reject "unindexed-data" Error.Size_mismatch (file "{}" "a");
  reject "overlap" Error.Invalid_offsets
    (file
       {|{"a":{"dtype":"U8","shape":[1],"data_offsets":[0,1]},"b":{"dtype":"U8","shape":[1],"data_offsets":[0,1]}}|}
       "a");
  reject "gap" Error.Invalid_offsets
    (file (header (desc ~shape:"[1]" ~offsets:"[1,2]" ())) "ab");
  let check_limit limits h =
    reject ~limits:(get limits) "limit" Error.Resource_limit (file h "")
  in
  check_limit (Limits.make ~max_header_bytes:1 ()) "{}";
  check_limit (Limits.make ~max_tensors:0 ()) (header (desc ()));
  check_limit (Limits.make ~max_rank:0 ()) (header (desc ()));
  check_limit (Limits.make ~max_name_bytes:0 ()) (header (desc ()));
  check_limit (Limits.make ~max_depth:1 ()) (header (desc ()));
  check_limit (Limits.make ~max_depth:2 ()) (header (desc ()));
  check_limit
    (Limits.make ~max_metadata_entries:0 ())
    {|{"__metadata__":{"a":"b"}}|};
  let tight =
    get
      (Limits.make ~max_tensors:1 ~max_rank:1 ~max_name_bytes:12 ~max_depth:3 ())
  in
  ignore (get (Memory.of_string ~limits:tight (file (header (desc ())) "")));
  (match Limits.make ~max_tensors:(-1) () with
  | Error _ -> ()
  | _ -> assert false);
  (match Memory.copy_tensor r "absent" with
  | Error e -> assert (Error.kind e = Error.Missing_tensor)
  | _ -> assert false);
  let precise =
    header (desc ~shape:"[9007199254740993]" ~offsets:"[0,9007199254740993]" ())
  in
  let ix =
    get
      (Index.decode_header
         ~file_size:
           (Int64.add 9007199254740993L
              (Int64.of_int (8 + String.length precise)))
         precise)
  in
  assert (
    Tensor.byte_length (Option.get (Index.find ix "x")) = 9007199254740993L);
  (match Memory.of_string (file (header (desc ~shape:"[1e0]" ())) "") with
  | Error e ->
      assert (Error.path e = Some "$[\"x\"][\"shape\"][0]");
      assert (Error.byte_offset e <> None)
  | _ -> assert false);
  Printf.printf
    "core: 13 dtypes, exact int64, %d malformed cases, layout and limits\n"
    (List.length bad_headers)

let () =
  let read name =
    let ic = open_in_bin ("fixtures/" ^ name) in
    Fun.protect
      ~finally:(fun () -> close_in ic)
      (fun () ->
        get (Memory.of_string (really_input_string ic (in_channel_length ic))))
  in
  List.iter
    (fun name -> ignore (read name))
    [
      "numpy-all.safetensors";
      "bf16.safetensors";
      "layout.safetensors";
      "empty.safetensors";
      "metadata.safetensors";
    ];
  let bits = get (Memory.copy_tensor (read "bf16.safetensors") "bits") in
  assert (
    Bytes.to_string bits
    = "\000\000\000\128\128\063\128\191\128\127\128\255\193\127\001\000");
  assert (
    get (Memory.copy_tensor (read "layout.safetensors") "z")
    = Bytes.of_string "\165");
  print_endline
    "offline corpus: 5 independent fixtures and hand-calculated byte goldens"
