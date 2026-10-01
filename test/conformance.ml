open Safetensors

let get = function
  | Ok x -> x
  | Error e -> failwith (Format.asprintf "%a" Error.pp e)

let quote s =
  match Jsont_bytesrw.encode_string Jsont.string s with
  | Ok s -> s
  | Error e -> failwith e

let hex b =
  let chars = "0123456789abcdef" in
  String.init
    (2 * Bytes.length b)
    (fun i ->
      let n = Char.code (Bytes.get b (i / 2)) in
      chars.[if i mod 2 = 0 then n lsr 4 else n land 15])

let inspect path =
  let ic = open_in_bin path in
  let data =
    Fun.protect
      ~finally:(fun () -> close_in ic)
      (fun () -> really_input_string ic (in_channel_length ic))
  in
  let memory = Memory.of_string data in
  match (memory, Safetensors_unix.open_file path) with
  | Error a, Error b ->
      if Error.kind a <> Error.kind b then
        failwith "memory/file rejection mismatch";
      Printf.printf
        {|{"ok":false,"kind":%s,"message":%s,"path":%s,"byte_offset":%s}%!|}
        (quote (Error.kind_name (Error.kind a)))
        (quote (Format.asprintf "%a" Error.pp a))
        (Option.fold ~none:"null" ~some:quote (Error.path a))
        (Option.fold ~none:"null"
           ~some:(fun n -> quote (Int64.to_string n))
           (Error.byte_offset a))
  | Error _, Ok f ->
      Safetensors_unix.close f;
      failwith "file reader accepted memory rejection"
  | Ok _, Error e ->
      failwith (Format.asprintf "file reader rejected: %a" Error.pp e)
  | Ok memory, Ok reader ->
      Fun.protect
        ~finally:(fun () -> Safetensors_unix.close reader)
        (fun () ->
          let index = Memory.index memory in
          if
            Index.metadata index
            <> Index.metadata (Safetensors_unix.index reader)
          then failwith "metadata mismatch";
          let metadata =
            Index.metadata index
            |> List.map (fun (k, v) -> quote k ^ ":" ^ quote v)
            |> String.concat ","
          in
          Printf.printf
            {|{"ok":true,"metadata":{%s},"data_start":%Ld,"tensors":[|} metadata
            (Index.data_start index);
          List.iteri
            (fun i t ->
              if i > 0 then print_char ',';
              let name = Tensor.name t in
              let bytes = get (Memory.copy_tensor memory name) in
              if get (Safetensors_unix.copy_tensor reader name) <> bytes then
                failwith "file copy mismatch";
              let n = Bytes.length bytes in
              let chunked = Bytes.create n in
              let rec read pos =
                if pos < n then (
                  let len = min (if pos = 0 then 3 else 4093) (n - pos) in
                  get
                    (Safetensors_unix.read_into reader name
                       ~tensor_offset:(Int64.of_int pos) chunked ~dst_off:pos
                       ~len);
                  read (pos + len))
              in
              read 0;
              if chunked <> bytes then failwith "chunked read mismatch";
              let b, e = Tensor.data_offsets t in
              Printf.printf
                {|{"name":%s,"dtype":%s,"shape":[%s],"data_offsets":[%Ld,%Ld],"data":%s}|}
                (quote name)
                (quote (Dtype.to_string (Tensor.dtype t)))
                (String.concat "," (List.map Int64.to_string (Tensor.shape t)))
                b e
                (quote (hex bytes)))
            (Index.tensors index);
          print_string "]}";
          print_newline ())

let () =
  if Array.length Sys.argv <> 2 then (
    prerr_endline "usage: conformance FILE";
    exit 2);
  inspect Sys.argv.(1)
