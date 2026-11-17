[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "OpenAI"]

open Safetensors

let get = function
  | Ok x -> x
  | Error e -> failwith (Format.asprintf "%a" Error.pp e)

let fields s = String.split_on_char ' ' s |> List.filter (( <> ) "")

let command_lines program arguments =
  let ic = Unix.open_process_args_in program arguments in
  let rec loop acc =
    match input_line ic with
    | line -> loop (line :: acc)
    | exception End_of_file -> List.rev acc
  in
  let lines = loop [] in
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 -> lines
  | _ -> failwith (program ^ " capability check failed")

let skip message =
  Printf.printf "SKIP large-file: %s\n%!" message;
  if Sys.getenv_opt "SAFETENSORS_REQUIRE_LARGE_FILE" = Some "1" then
    failwith "required large-file capability unavailable";
  exit 0

let () =
  let small32 = Array.length Sys.argv = 2 && Sys.argv.(1) = "--32-bit" in
  if small32 && Sys.word_size <> 32 then
    failwith "32-bit copy limit probe requires a true 32-bit OCaml runtime";
  if not small32 && Sys.word_size <> 64 then skip "64-bit address space required";
  let path = Filename.temp_file "safetensors-large-" ".safetensors" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      let free =
        match List.rev (command_lines "df" [| "df"; "-Pk"; path |]) with
        | line :: _ -> Int64.of_string (List.nth (fields line) 3)
        | [] -> failwith "df returned no capacity information"
      in
      if free < 65536L then skip "less than 64 MiB free disk";
      let size =
        if small32 then Int64.succ (Int64.of_int Sys.max_string_length)
        else 8_589_934_592L
      in
      let header =
        Printf.sprintf
          {|{"big":{"dtype":"U8","shape":[%Ld],"data_offsets":[0,%Ld]}}|}
          size size
      in
      let prefix = Bytes.create (8 + String.length header) in
      Bytes.set_int64_le prefix 0 (Int64.of_int (String.length header));
      Bytes.blit_string header 0 prefix 8 (String.length header);
      let data_start = Int64.of_int (Bytes.length prefix) in
      let fd = Unix.openfile path [ Unix.O_WRONLY ] 0 in
      Fun.protect
        ~finally:(fun () -> Unix.close fd)
        (fun () ->
          assert (Unix.write fd prefix 0 (Bytes.length prefix) = Bytes.length prefix);
          Unix.LargeFile.ftruncate fd (Int64.add data_start size));
      let allocated =
        match command_lines "du" [| "du"; "-k"; path |] with
        | line :: _ -> Int64.of_string (List.hd (fields (String.map (fun c -> if c = '\t' then ' ' else c) line)))
        | [] -> failwith "du returned no allocation information"
      in
      if allocated > 1024L then skip "filesystem did not create a sparse file";
      let positions =
        if small32 then [ 0L; Int64.pred size ]
        else [ 0L; 2_147_483_665L; Int64.pred size ]
      in
      let fd = Unix.openfile path [ Unix.O_WRONLY ] 0 in
      Fun.protect
        ~finally:(fun () -> Unix.close fd)
        (fun () ->
          List.iteri
            (fun i position ->
              ignore (Unix.LargeFile.lseek fd (Int64.add data_start position) Unix.SEEK_SET);
              assert (Unix.write fd (Bytes.make 1 (Char.chr (65 + i))) 0 1 = 1))
            positions);
      let before = Gc.allocated_bytes () in
      let mapped = get (Safetensors_unix.Mmap.open_file path) in
      let view = get (Memory.tensor_view mapped "big") in
      assert (Int64.of_int (Bigarray.Array1.dim view) = size);
      get
        (Safetensors_unix.with_file path (fun reader ->
             List.iteri
               (fun i position ->
                 let expected = Char.chr (65 + i) in
                 assert (Bigarray.Array1.get view (Int64.to_int position) = expected);
                 let byte = Bytes.create 1 in
                 get (Safetensors_unix.read_into reader "big" ~tensor_offset:position byte ~dst_off:0 ~len:1);
                 assert (Bytes.get byte 0 = expected))
               positions;
             Ok ()));
      assert (Gc.allocated_bytes () -. before < 1_000_000.);
      if small32 then (
        match Memory.copy_tensor mapped "big" with
        | Error e ->
            assert (Error.kind e = Error.Resource_limit);
            assert (Error.tensor e = Some "big")
        | Ok _ -> failwith "oversized 32-bit tensor copy accepted");
      Printf.printf
        "large-file: word_size=%d max_string_length=%d mapped=%Ld sparse_kib=%Ld selected bytes verified\n%!"
        Sys.word_size Sys.max_string_length size allocated)
