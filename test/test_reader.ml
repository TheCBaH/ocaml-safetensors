[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Safetensors

let get = function
  | Ok x -> x
  | Error e -> failwith (Format.asprintf "%a" Error.pp e)

let expect kind = function
  | Error e when Error.kind e = kind -> ()
  | Error e ->
      failwith
        (Format.asprintf "expected %s, got %a" (Error.kind_name kind) Error.pp e)
  | Ok _ -> failwith "expected error"

let file h data =
  let p = Bytes.create 8 in
  Bytes.set_int64_le p 0 (Int64.of_int (String.length h));
  Bytes.to_string p ^ h ^ data

let with_temp data f =
  let path = Filename.temp_file "safetensors-test-" ".safetensors" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      let out = open_out_bin path in
      output_string out data;
      close_out out;
      f path)

let sample =
  file {|{"x":{"dtype":"U8","shape":[5],"data_offsets":[0,5]}}|} "abcde"

let fd_count () =
  if Sys.file_exists "/proc/self/fd" then
    Array.length (Sys.readdir "/proc/self/fd")
  else 0

let () =
  let calls = ref 0 in
  let read _ dst off len =
    incr calls;
    if !calls = 1 then raise (Unix.Unix_error (Unix.EINTR, "read", "injected"));
    let n = min 2 len in
    Bytes.fill dst off n 'a';
    n
  in
  let b = Bytes.make 7 'x' in
  get (Safetensors_io.read_exact ~read Unix.stdin b 1 5);
  assert (!calls = 4 && Bytes.to_string b = "xaaaaax");
  expect Error.Truncated
    (Safetensors_io.read_exact ~read:(fun _ _ _ _ -> 0) Unix.stdin b 0 1);
  get
    (Safetensors_io.read_exact
       ~read:(fun _ _ _ _ -> assert false)
       Unix.stdin b 0 0);
  (try
     ignore
       (Safetensors_io.read_exact
          ~read:(fun _ _ _ _ -> raise (Unix.Unix_error (Unix.EIO, "read", "")))
          Unix.stdin b 0 1);
     assert false
   with Unix.Unix_error (Unix.EIO, _, _) -> ());
  with_temp sample (fun path ->
      let r = get (Safetensors_unix.open_file path) in
      let ix = Safetensors_unix.index r in
      assert (get (Safetensors_unix.copy_tensor r "x") = Bytes.of_string "abcde");
      let b = Bytes.make 9 '-' in
      get
        (Safetensors_unix.read_into r "x" ~tensor_offset:1L b ~dst_off:2 ~len:3);
      assert (Bytes.to_string b = "--bcd----");
      get
        (Safetensors_unix.read_into r "x" ~tensor_offset:5L b ~dst_off:9 ~len:0);
      expect Error.Invalid_argument
        (Safetensors_unix.read_into r "x" ~tensor_offset:5L b ~dst_off:0 ~len:1);
      expect Error.Invalid_argument
        (Safetensors_unix.read_into r "x" ~tensor_offset:(-1L) b ~dst_off:0
           ~len:1);
      expect Error.Invalid_argument
        (Safetensors_unix.read_into r "x" ~tensor_offset:0L b ~dst_off:(-1)
           ~len:1);
      expect Error.Invalid_argument
        (Safetensors_unix.read_into r "x" ~tensor_offset:0L b ~dst_off:1
           ~len:max_int);
      expect Error.Missing_tensor (Safetensors_unix.copy_tensor r "missing");
      Unix.truncate path (String.length sample - 2);
      expect Error.Truncated (Safetensors_unix.copy_tensor r "x");
      Safetensors_unix.close r;
      Safetensors_unix.close r;
      expect Error.Closed (Safetensors_unix.copy_tensor r "x");
      assert (List.length (Index.tensors ix) = 1));
  let before = fd_count () in
  for _i = 1 to 100 do
    with_temp "short" (fun p ->
        expect Error.Truncated (Safetensors_unix.open_file p));
    with_temp sample (fun p ->
        try
          ignore (Safetensors_unix.with_file p (fun _ -> raise Exit));
          assert false
        with Exit -> ())
  done;
  assert (before = fd_count ());
  expect Error.Invalid_argument (Safetensors_unix.open_file ".");
  expect Error.Io
    (Safetensors_unix.open_file "/missing-safetensors-test-dir/file");
  print_endline "unix: short reads, EINTR, truncation and lifecycle"

type tensor = { name : string; dtype : string; shape : int list; data : string }

let render tensors =
  let offset = ref 0 in
  let entries =
    List.map
      (fun t ->
        let start = !offset in
        offset := start + String.length t.data;
        Printf.sprintf {|%S:{"dtype":%S,"shape":[%s],"data_offsets":[%d,%d]}|}
          t.name t.dtype
          (String.concat "," (List.map string_of_int t.shape))
          start !offset)
      tensors
  in
  file
    ("{\"__metadata__\":{\"test\":\"seeded\"},"
    ^ String.concat "," (List.rev entries)
    ^ "}")
    (String.concat "" (List.map (fun t -> t.data) tensors))

let bigstring data =
  Bigarray.Array1.init Bigarray.Char Bigarray.c_layout (String.length data)
    (String.get data)

let snapshot index =
  ( Index.metadata index,
    Index.data_start index,
    List.map
      (fun t ->
        (Tensor.name t, Tensor.dtype t, Tensor.shape t, Tensor.data_offsets t))
      (Index.tensors index) )

let check tensors =
  let bytes = render tensors in
  let mem = get (Memory.of_string bytes) in
  let big = get (Memory.of_bigstring (bigstring bytes)) in
  with_temp bytes (fun path ->
      let mapped = get (Safetensors_unix.Mmap.open_file path) in
      get
        (Safetensors_unix.with_file path (fun f ->
             let index = snapshot (Memory.index mem) in
             List.iter
               (fun m -> assert (snapshot (Memory.index m) = index))
               [ big; mapped ];
             assert (snapshot (Safetensors_unix.index f) = index);
             List.iter
               (fun m ->
                 expect Error.Missing_tensor (Memory.copy_tensor m "missing");
                 expect Error.Missing_tensor (Memory.tensor_view m "missing"))
               [ mem; big; mapped ];
             expect Error.Missing_tensor (Safetensors_unix.copy_tensor f "missing");
             List.iter
               (fun t ->
                 List.iter
                   (fun m ->
                     let copy = get (Memory.copy_tensor m t.name) in
                     assert (Bytes.to_string copy = t.data);
                     let view = get (Memory.tensor_view m t.name) in
                     assert (Bigarray.Array1.dim view = String.length t.data);
                     String.iteri
                       (fun i c -> assert (Bigarray.Array1.get view i = c))
                       t.data;
                     Bytes.fill copy 0 (Bytes.length copy) 'Q';
                     assert (Bytes.to_string (get (Memory.copy_tensor m t.name)) = t.data))
                   [ mem; big; mapped ];
                 assert (
                   Bytes.to_string (get (Safetensors_unix.copy_tensor f t.name))
                   = t.data);
                 let desc = Option.get (Index.find (Memory.index mem) t.name) in
                 assert (Tensor.shape desc = List.map Int64.of_int t.shape);
                 assert (Dtype.to_string (Tensor.dtype desc) = t.dtype);
                 let n = String.length t.data in
                 let chunks = Bytes.make n '\000' in
                 let rec loop pos =
                   if pos < n then (
                     let len = min (1 + (pos mod 17)) (n - pos) in
                     get
                       (Safetensors_unix.read_into f t.name
                          ~tensor_offset:(Int64.of_int pos) chunks ~dst_off:pos
                          ~len);
                     loop (pos + len))
                 in
                 loop 0;
                 assert (Bytes.to_string chunks = t.data))
               tensors;
             Ok ())))

let () =
  let seed =
    match Sys.getenv_opt "SAFETENSORS_SEED" with
    | None -> 1337
    | Some s -> int_of_string s
  in
  let cases =
    match Sys.getenv_opt "SAFETENSORS_CASES" with
    | None -> 1000
    | Some s -> int_of_string s
  in
  let rng = Random.State.make [| seed |] in
  let dtypes =
    [|
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
    |]
  in
  for case = 1 to cases do
    let tensors =
      List.init
        (1 + Random.State.int rng 6)
        (fun i ->
          let dtype, width =
            dtypes.(Random.State.int rng (Array.length dtypes))
          in
          let shape =
            List.init (Random.State.int rng 5) (fun _ -> Random.State.int rng 5)
          in
          let n = width * List.fold_left ( * ) 1 shape in
          {
            name = Printf.sprintf "tensor.%d" i;
            dtype;
            shape;
            data = String.init n (fun _ -> Char.chr (Random.State.int rng 256));
          })
    in
    (try check tensors
     with e ->
       let fails ts =
         try
           check ts;
           false
         with _ -> true
       in
       let rec shrink ts =
         match ts with
         | _ :: (_ :: _ as tail) when fails tail -> shrink tail
         | _ -> ts
       in
       let small = render (shrink tensors) in
       let path =
         match Sys.getenv_opt "SAFETENSORS_FAILURE_FILE" with
         | Some p -> p
         | None -> "property-failure.safetensors"
       in
       let out = open_out_bin path in
       output_string out small;
       close_out out;
       failwith
         (Printf.sprintf "seed=%d case=%d regression=%s: %s" seed case path
            (Printexc.to_string e)));
    let random =
      String.init (Random.State.int rng 512) (fun _ ->
          Char.chr (Random.State.int rng 256))
    in
    ignore (Memory.of_string random);
    let mutated = Bytes.of_string (render tensors) in
    let i = Random.State.int rng (Bytes.length mutated) in
    Bytes.set mutated i (Char.chr (Random.State.int rng 256));
    ignore (Memory.of_string (Bytes.to_string mutated))
  done;
  Printf.printf
    "properties: seed=%d cases=%d, byte parity and malformed-input mutations\n"
    seed cases

let () =
  let data =
    file
      {|{"start":{"dtype":"U8","shape":[0],"data_offsets":[0,0]},"a":{"dtype":"U8","shape":[3],"data_offsets":[0,3]},"b":{"dtype":"U8","shape":[2],"data_offsets":[3,5]},"end":{"dtype":"U8","shape":[0],"data_offsets":[5,5]}}|}
      "abcde"
  in
  with_temp data (fun path ->
      let surviving =
        let mapped = get (Safetensors_unix.Mmap.open_file path) in
        List.iter
          (fun name ->
            let view = get (Memory.tensor_view mapped name) in
            assert (Bigarray.Array1.dim view = 0))
          [ "start"; "end" ];
        get (Memory.tensor_view mapped "b")
      in
      Gc.full_major ();
      Gc.compact ();
      assert (Bigarray.Array1.get surviving 0 = 'd');
      assert (Bigarray.Array1.get surviving 1 = 'e');
      (* Test-only mutation proves COW aliasing without changing the file. *)
      let mapped = get (Safetensors_unix.Mmap.open_file path) in
      let first = get (Memory.tensor_view mapped "b") in
      let second = get (Memory.tensor_view mapped "b") in
      Bigarray.Array1.set first 0 'Z';
      assert (Bigarray.Array1.get second 0 = 'Z');
      let fresh = get (Safetensors_unix.Mmap.open_file path) in
      assert (Bytes.to_string (get (Memory.copy_tensor fresh "b")) = "de"));
  with_temp "short" (fun path ->
      expect Error.Truncated (Safetensors_unix.Mmap.open_file path));
  let view =
    let backing = bigstring data in
    let m = get (Memory.of_bigstring backing) in
    let view = get (Memory.tensor_view m "b") in
    Bigarray.Array1.set backing (String.length data - 2) 'Z';
    assert (Bigarray.Array1.get view 0 = 'Z');
    view
  in
  Gc.full_major ();
  Gc.compact ();
  assert (Bigarray.Array1.get view 0 = 'Z');
  let copied = get (Memory.of_string data) in
  let first = get (Memory.tensor_view copied "b") in
  let second = get (Memory.tensor_view copied "b") in
  Bigarray.Array1.set first 0 'Z';
  assert (Bigarray.Array1.get second 0 = 'd');
  assert (Bytes.to_string (get (Memory.copy_tensor copied "b")) = "de");
  print_endline "views: boundary empties, alias/copy isolation and GC survival"
