module Error = struct
  type kind =
    | Io
    | Truncated
    | Invalid_header
    | Invalid_json
    | Duplicate_member
    | Invalid_integer
    | Unsupported_dtype
    | Invalid_offsets
    | Size_mismatch
    | Resource_limit
    | Missing_tensor
    | Closed
    | Invalid_argument

  type t = {
    kind : kind;
    message : string;
    tensor : string option;
    byte_offset : int64 option;
    path : string option;
  }

  let make ?tensor ?byte_offset ?path kind message =
    { kind; message; tensor; byte_offset; path }

  let kind e = e.kind
  let message e = e.message
  let tensor e = e.tensor
  let byte_offset e = e.byte_offset
  let path e = e.path

  let kind_name = function
    | Io -> "io"
    | Truncated -> "truncated"
    | Invalid_header -> "invalid_header"
    | Invalid_json -> "invalid_json"
    | Duplicate_member -> "duplicate_member"
    | Invalid_integer -> "invalid_integer"
    | Unsupported_dtype -> "unsupported_dtype"
    | Invalid_offsets -> "invalid_offsets"
    | Size_mismatch -> "size_mismatch"
    | Resource_limit -> "resource_limit"
    | Missing_tensor -> "missing_tensor"
    | Closed -> "closed"
    | Invalid_argument -> "invalid_argument"

  let pp ppf e =
    Format.fprintf ppf "%s: %s" (kind_name e.kind) e.message;
    Option.iter (fun n -> Format.fprintf ppf " (tensor %S)" n) e.tensor;
    Option.iter (fun n -> Format.fprintf ppf " at byte %Ld" n) e.byte_offset;
    Option.iter (fun p -> Format.fprintf ppf " [%s]" p) e.path
end

exception Failure of Error.t

let fail ?tensor ?byte_offset ?path kind message =
  raise (Failure (Error.make ?tensor ?byte_offset ?path kind message))

let protect f = try Ok (f ()) with Failure e -> Error e

module Limits = struct
  type t = {
    max_header_bytes : int;
    max_tensors : int;
    max_rank : int;
    max_name_bytes : int;
    max_metadata_entries : int;
    max_depth : int;
  }

  let default =
    {
      max_header_bytes = 100_000_000;
      max_tensors = 100_000;
      max_rank = 64;
      max_name_bytes = 4096;
      max_metadata_entries = 100_000;
      max_depth = 16;
    }

  let make ?(max_header_bytes = default.max_header_bytes)
      ?(max_tensors = default.max_tensors) ?(max_rank = default.max_rank)
      ?(max_name_bytes = default.max_name_bytes)
      ?(max_metadata_entries = default.max_metadata_entries)
      ?(max_depth = default.max_depth) () =
    protect (fun () ->
        if
          List.exists
            (fun n -> n < 0)
            [
              max_header_bytes;
              max_tensors;
              max_rank;
              max_name_bytes;
              max_metadata_entries;
              max_depth;
            ]
          || max_tensors = max_int
        then
          fail Error.Invalid_argument
            "limits must be nonnegative; max_tensors must be below max_int";
        {
          max_header_bytes;
          max_tensors;
          max_rank;
          max_name_bytes;
          max_metadata_entries;
          max_depth;
        })

  let max_header_bytes t = t.max_header_bytes
end

module Dtype = struct
  type t =
    | Bool
    | U8
    | I8
    | U16
    | I16
    | U32
    | I32
    | U64
    | I64
    | F16
    | BF16
    | F32
    | F64

  let all =
    [
      ("BOOL", Bool);
      ("U8", U8);
      ("I8", I8);
      ("U16", U16);
      ("I16", I16);
      ("U32", U32);
      ("I32", I32);
      ("U64", U64);
      ("I64", I64);
      ("F16", F16);
      ("BF16", BF16);
      ("F32", F32);
      ("F64", F64);
    ]

  let of_string s =
    match List.assoc_opt s all with
    | Some d -> Ok d
    | None -> Error (Error.make Error.Unsupported_dtype s)

  let to_string d = fst (List.find (fun (_, v) -> v = d) all)

  let byte_width = function
    | Bool | U8 | I8 -> 1
    | U16 | I16 | F16 | BF16 -> 2
    | U32 | I32 | F32 -> 4
    | U64 | I64 | F64 -> 8
end

module Tensor = struct
  type t = {
    name : string;
    dtype : Dtype.t;
    shape : int64 list;
    begin_ : int64;
    end_ : int64;
  }

  let name t = t.name
  let dtype t = t.dtype
  let shape t = t.shape
  let data_offsets t = (t.begin_, t.end_)
  let byte_length t = Int64.sub t.end_ t.begin_
end

module Names = Map.Make (String)

type field = Text of string | Integers of int64 list

let location meta =
  let loc = Jsont.Meta.textloc meta in
  if Jsont.Textloc.is_none loc then None
  else Some (Int64.add 8L (Int64.of_int (Jsont.Textloc.first_byte loc)))

let decode_json limits header =
  let pending = ref None in
  let abort meta kind message =
    pending := Some kind;
    Jsont.Error.msg meta message
  in
  let check_depth depth =
    if depth > limits.Limits.max_depth then
      abort Jsont.Meta.none Error.Resource_limit "JSON depth limit exceeded"
  in
  let number =
    Jsont.Base.number
      (Jsont.Base.map ~kind:"nonnegative integer"
         ~dec:(fun meta _rounded ->
           let loc = Jsont.Meta.textloc meta in
           let first = Jsont.Textloc.first_byte loc in
           let last = Jsont.Textloc.last_byte loc in
           if
             Jsont.Textloc.is_none loc || first < 0 || last < first
             || last >= String.length header
           then
             abort meta Error.Invalid_integer "missing integer source location";
           let value = ref 0L in
           for i = first to last do
             let c = header.[i] in
             if c < '0' || c > '9' then
               abort meta Error.Invalid_integer
                 "expected a nonnegative decimal integer token";
             let digit = Int64.of_int (Char.code c - 48) in
             if !value > Int64.div (Int64.sub Int64.max_int digit) 10L then
               abort meta Error.Resource_limit
                 "integer exceeds signed int64 range";
             value := Int64.add (Int64.mul !value 10L) digit
           done;
           !value)
         ())
  in
  let array =
    Jsont.Array.array
      (Jsont.Array.map number
         ~dec_empty:(fun () ->
           check_depth 3;
           [])
         ~dec_skip:(fun i _ ->
           if i >= max 2 limits.Limits.max_rank then
             abort Jsont.Meta.none Error.Resource_limit
               "integer array limit exceeded";
           false)
         ~dec_add:(fun _ n ns -> n :: ns)
         ~dec_finish:(fun _ _ ns -> Integers (List.rev ns)))
  in
  let text = Jsont.map ~dec:(fun s -> Text s) Jsont.string in
  let field = Jsont.any ~dec_string:text ~dec_array:array () in
  let object_map ~depth ~max_members value =
    let members =
      Jsont.Object.Mems.map value
        ~dec_empty:(fun () ->
          check_depth depth;
          (0, Names.empty))
        ~dec_add:(fun meta name value (count, values) ->
          if String.length name > limits.Limits.max_name_bytes then
            abort meta Error.Resource_limit "member name limit exceeded";
          if Names.mem name values then
            abort meta Error.Duplicate_member ("duplicate member: " ^ name);
          if count >= max_members then
            abort meta Error.Resource_limit "object member limit exceeded";
          (count + 1, Names.add name value values))
        ~dec_finish:(fun _ (_, values) -> values)
    in
    Jsont.Object.map Fun.id
    |> Jsont.Object.keep_unknown members
    |> Jsont.Object.finish
  in
  let record =
    object_map ~depth:2
      ~max_members:(max 3 limits.Limits.max_metadata_entries)
      field
  in
  let root =
    object_map ~depth:1 ~max_members:(limits.Limits.max_tensors + 1) record
  in
  match Jsont_bytesrw.decode_string' ~locs:true root header with
  | Ok root -> root
  | Error ((context, meta, _) as error) ->
      let path =
        "$"
        ^ String.concat ""
            (List.map
               (fun (_, index) ->
                 match index with
                 | Jsont.Path.Mem (name, _) -> Printf.sprintf "[%S]" name
                 | Jsont.Path.Nth (i, _) -> Printf.sprintf "[%d]" i)
               context)
      in
      let tensor =
        match context with
        | (_, Jsont.Path.Mem (name, _)) :: _ when name <> "__metadata__" ->
            Some name
        | _ -> None
      in
      fail ?tensor ?byte_offset:(location meta) ~path
        (Option.value !pending ~default:Error.Invalid_json)
        (Jsont.Error.to_string error)

module Index = struct
  type t = {
    metadata : (string * string) list;
    tensors : Tensor.t Names.t;
    data_start : int64;
  }

  let metadata t = t.metadata
  let tensors t = List.map snd (Names.bindings t.tensors)
  let find t name = Names.find_opt name t.tensors
  let data_start t = t.data_start

  let header_length ?(limits = Limits.default) ~file_size prefix =
    protect (fun () ->
        if String.length prefix <> 8 || file_size < 8L then
          fail Error.Truncated "expected an eight-byte prefix";
        let n = String.get_int64_le prefix 0 in
        if n < 0L then
          fail Error.Resource_limit
            "unsigned header length exceeds signed int64";
        if
          n > Int64.of_int limits.Limits.max_header_bytes
          || n > Int64.of_int Sys.max_string_length
        then fail Error.Resource_limit "header allocation limit exceeded";
        if n > Int64.sub file_size 8L then
          fail Error.Truncated "header extends beyond file";
        Int64.to_int n)

  let decode_header ?(limits = Limits.default) ~file_size header =
    protect (fun () ->
        let n = String.length header in
        if n > limits.Limits.max_header_bytes then
          fail Error.Resource_limit "header allocation limit exceeded";
        let data_start = Int64.add 8L (Int64.of_int n) in
        if file_size < data_start then
          fail Error.Truncated "header extends beyond file";
        let payload_size = Int64.sub file_size data_start in
        let root = decode_json limits header in
        let metadata, records =
          match Names.find_opt "__metadata__" root with
          | None -> ([], root)
          | Some m ->
              if Names.cardinal m > limits.Limits.max_metadata_entries then
                fail ~path:"$[\"__metadata__\"]" Error.Resource_limit
                  "metadata entry limit exceeded";
              let entries =
                Names.bindings m
                |> List.map (fun (name, value) ->
                    match value with
                    | Text s -> (name, s)
                    | Integers _ ->
                        fail
                          ~path:(Printf.sprintf "$[\"__metadata__\"][%S]" name)
                          Error.Invalid_header "metadata values must be strings")
              in
              (entries, Names.remove "__metadata__" root)
        in
        if Names.cardinal records > limits.Limits.max_tensors then
          fail Error.Resource_limit "tensor count limit exceeded";
        let tensors =
          Names.mapi
            (fun name fields ->
              let bad ?field kind message =
                let path =
                  Printf.sprintf "$[%S]" name
                  ^
                  match field with
                  | None -> ""
                  | Some f -> Printf.sprintf "[%S]" f
                in
                fail ~tensor:name ~path kind message
              in
              Names.iter
                (fun key _ ->
                  if not (List.mem key [ "dtype"; "shape"; "data_offsets" ])
                  then
                    bad ~field:key Error.Invalid_header "unknown tensor field")
                fields;
              let required key =
                match Names.find_opt key fields with
                | Some v -> v
                | None ->
                    bad ~field:key Error.Invalid_header "missing tensor field"
              in
              let dtype =
                match required "dtype" with
                | Text s -> (
                    match Dtype.of_string s with
                    | Ok d -> d
                    | Error _ -> bad ~field:"dtype" Error.Unsupported_dtype s)
                | _ ->
                    bad ~field:"dtype" Error.Invalid_header
                      "dtype must be a string"
              in
              let shape =
                match required "shape" with
                | Integers ns -> ns
                | _ ->
                    bad ~field:"shape" Error.Invalid_header
                      "shape must be an integer array"
              in
              if List.length shape > limits.Limits.max_rank then
                bad ~field:"shape" Error.Resource_limit "rank limit exceeded";
              let begin_, end_ =
                match required "data_offsets" with
                | Integers [ b; e ] -> (b, e)
                | _ ->
                    bad ~field:"data_offsets" Error.Invalid_offsets
                      "expected two offsets"
              in
              if end_ < begin_ || end_ > payload_size then
                bad ~field:"data_offsets" Error.Invalid_offsets
                  "range is reversed or outside payload";
              let mul a b =
                if b <> 0L && a > Int64.div Int64.max_int b then
                  bad ~field:"shape" Error.Resource_limit
                    "tensor byte count overflows int64";
                Int64.mul a b
              in
              let count =
                if List.mem 0L shape then 0L else List.fold_left mul 1L shape
              in
              let expected =
                mul count (Int64.of_int (Dtype.byte_width dtype))
              in
              if Int64.sub end_ begin_ <> expected then
                bad Error.Size_mismatch
                  "shape and dtype disagree with byte range";
              ({ name; dtype; shape; begin_; end_ } : Tensor.t))
            records
        in
        let by_offset =
          Names.bindings tensors |> List.map snd
          |> List.sort (fun a b ->
              compare (Tensor.data_offsets a) (Tensor.data_offsets b))
        in
        let cursor =
          List.fold_left
            (fun cursor tensor ->
              let b, e = Tensor.data_offsets tensor in
              if b <> cursor then
                fail ~tensor:(Tensor.name tensor) Error.Invalid_offsets
                  "payload ranges overlap or leave a gap";
              e)
            0L by_offset
        in
        if cursor <> payload_size then
          fail Error.Size_mismatch "payload is not completely indexed";
        { metadata; tensors; data_start })
end

module Memory = struct
  type t = { data : string; index : Index.t }

  let index t = t.index

  let of_string ?limits data =
    if String.length data < 8 then
      Error (Error.make Error.Truncated "expected an eight-byte prefix")
    else
      let file_size = Int64.of_int (String.length data) in
      match Index.header_length ?limits ~file_size (String.sub data 0 8) with
      | Error e -> Error e
      | Ok n -> (
          match
            Index.decode_header ?limits ~file_size (String.sub data 8 n)
          with
          | Error e -> Error e
          | Ok index -> Ok { data; index })

  let copy_tensor t name =
    match Index.find t.index name with
    | None ->
        Error (Error.make ~tensor:name Error.Missing_tensor "tensor not found")
    | Some tensor ->
        let b, _ = Tensor.data_offsets tensor in
        let start = Int64.to_int (Int64.add (Index.data_start t.index) b) in
        let length = Int64.to_int (Tensor.byte_length tensor) in
        let bytes = Bytes.create length in
        Bytes.blit_string t.data start bytes 0 length;
        Ok bytes
end
