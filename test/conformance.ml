[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

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

let bigstring s =
  Bigarray.Array1.init Bigarray.Char Bigarray.c_layout (String.length s)
    (String.get s)

let descriptor t =
  (Tensor.name t, Tensor.dtype t, Tensor.shape t, Tensor.data_offsets t)

let check_index expected actual =
  if Index.metadata expected <> Index.metadata actual
     || Index.data_start expected <> Index.data_start actual
     || List.map descriptor (Index.tensors expected)
        <> List.map descriptor (Index.tensors actual)
  then failwith "reader index mismatch"

let check_memory expected memory name =
  if get (Memory.copy_tensor memory name) <> expected then
    failwith "memory copy mismatch";
  let view = get (Memory.tensor_view memory name) in
  if Bigarray.Array1.dim view <> Bytes.length expected then
    failwith "view length mismatch";
  Bytes.iteri
    (fun i c ->
      if Bigarray.Array1.get view i <> c then failwith "view byte mismatch")
    expected

let inspect path =
  let ic = open_in_bin path in
  let data =
    Fun.protect
      ~finally:(fun () -> close_in ic)
      (fun () -> really_input_string ic (in_channel_length ic))
  in
  let memory = Memory.of_string data in
  let big = Memory.of_bigstring (bigstring data) in
  let mapped = Safetensors_unix.Mmap.open_file path in
  let reader = Safetensors_unix.open_file path in
  Fun.protect
    ~finally:(fun () ->
      match reader with Ok r -> Safetensors_unix.close r | Error _ -> ())
    (fun () ->
      match (memory, big, mapped, reader) with
      | Error a, Error b, Error c, Error d ->
          List.iter
            (fun e ->
              if Error.kind a <> Error.kind e then
                failwith "four-reader rejection mismatch")
            [ b; c; d ];
          Printf.printf
            {|{"ok":false,"kind":%s,"message":%s,"path":%s,"byte_offset":%s}%!|}
            (quote (Error.kind_name (Error.kind a)))
            (quote (Format.asprintf "%a" Error.pp a))
            (Option.fold ~none:"null" ~some:quote (Error.path a))
            (Option.fold ~none:"null"
               ~some:(fun n -> quote (Int64.to_string n))
               (Error.byte_offset a))
      | Ok memory, Ok big, Ok mapped, Ok reader ->
          let index = Memory.index memory in
          List.iter (check_index index)
            [ Memory.index big; Memory.index mapped; Safetensors_unix.index reader ];
          let metadata =
            Index.metadata index
            |> List.map (fun (k, v) -> quote k ^ ":" ^ quote v)
            |> String.concat ","
          in
          Printf.printf
            {|{"ok":true,"readers":4,"metadata":{%s},"data_start":%Ld,"tensors":[|}
            metadata (Index.data_start index);
          List.iteri
            (fun i t ->
              if i > 0 then print_char ',';
              let name = Tensor.name t in
              let bytes = get (Memory.copy_tensor memory name) in
              List.iter (fun m -> check_memory bytes m name) [ memory; big; mapped ];
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
                b e (quote (hex bytes)))
            (Index.tensors index);
          print_endline "]}"
      | _ -> failwith "four-reader acceptance mismatch")

let () =
  if Array.length Sys.argv <> 2 then (
    prerr_endline "usage: conformance FILE";
    exit 2);
  inspect Sys.argv.(1)
