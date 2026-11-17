[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

let json_quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | c when Char.code c < 0x20 -> Printf.bprintf b "\\u%04x" (Char.code c)
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

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
  let json_path = path

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
    Option.iter
      (fun n -> Format.fprintf ppf " (tensor %s)" (json_quote n))
      e.tensor;
    Option.iter (fun n -> Format.fprintf ppf " at byte %Ld" n) e.byte_offset;
    Option.iter (fun p -> Format.fprintf ppf " [%s]" p) e.path
end

exception Decode_failure of Error.t

let fail ?tensor ?byte_offset ?path kind message =
  raise (Decode_failure (Error.make ?tensor ?byte_offset ?path kind message))

let protect f = try Ok (f ()) with Decode_failure e -> Error e

module Limits = struct
  type t = {
    max_header_bytes : int;
    max_tensors : int;
    max_rank : int;
    max_name_bytes : int;
    max_metadata_entries : int;
  }

  let default =
    {
      max_header_bytes = 100_000_000;
      max_tensors = 100_000;
      max_rank = 64;
      max_name_bytes = 4096;
      max_metadata_entries = 100_000;
    }

  let make ?(max_header_bytes = default.max_header_bytes)
      ?(max_tensors = default.max_tensors) ?(max_rank = default.max_rank)
      ?(max_name_bytes = default.max_name_bytes)
      ?(max_metadata_entries = default.max_metadata_entries) () =
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
        })

  let max_header_bytes t = t.max_header_bytes
  let max_tensors t = t.max_tensors
  let max_rank t = t.max_rank
  let max_name_bytes t = t.max_name_bytes
  let max_metadata_entries t = t.max_metadata_entries
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
    | F8_E5M2
    | F8_E4M3
    | F8_E8M0
    | F8_E4M3FNUZ
    | F8_E5M2FNUZ
    | C64

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
      ("F8_E5M2", F8_E5M2);
      ("F8_E4M3", F8_E4M3);
      ("F8_E8M0", F8_E8M0);
      ("F8_E4M3FNUZ", F8_E4M3FNUZ);
      ("F8_E5M2FNUZ", F8_E5M2FNUZ);
      ("C64", C64);
    ]

  let of_string s =
    match List.assoc_opt s all with
    | Some d -> Ok d
    | None ->
        Error (Error.make Error.Unsupported_dtype ("unsupported dtype: " ^ s))

  let to_string d = fst (List.find (fun (_, v) -> v = d) all)

  let byte_width = function
    | Bool | U8 | I8 | F8_E5M2 | F8_E4M3 | F8_E8M0 | F8_E4M3FNUZ | F8_E5M2FNUZ
      ->
        1
    | U16 | I16 | F16 | BF16 -> 2
    | U32 | I32 | F32 -> 4
    | U64 | I64 | F64 | C64 -> 8
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

type 'a located = { value : 'a; meta : Jsont.Meta.t }

type descriptor = {
  dtype : string located option;
  shape : int64 list located option;
  offsets : int64 list located option;
  meta : Jsont.Meta.t;
}

let location meta =
  let loc = Jsont.Meta.textloc meta in
  if Jsont.Textloc.is_none loc then None
  else Some (Int64.add 8L (Int64.of_int (Jsont.Textloc.first_byte loc)))

let member_path name = "[" ^ json_quote name ^ "]"

let decode_json limits header =
  let pending = ref None in
  let abort meta kind message =
    pending := Some kind;
    Jsont.Error.msg meta message
  in
  let reject meta _ = abort meta Error.Invalid_header "unexpected JSON value" in
  let rejected_array () =
    Jsont.Array.array
      (Jsont.Array.map Jsont.number
         ~dec_empty:(fun () -> reject Jsont.Meta.none ())
         ~dec_add:(fun _ _ () -> ())
         ~dec_finish:(fun _ _ () -> assert false))
  in
  let rejected_object () =
    let members =
      Jsont.Object.Mems.map Jsont.number
        ~dec_empty:(fun () -> reject Jsont.Meta.none ())
        ~dec_add:(fun _ _ _ () -> ())
        ~dec_finish:(fun _ () -> assert false)
    in
    Jsont.Object.map Fun.id
    |> Jsont.Object.keep_unknown members
    |> Jsont.Object.finish
  in
  let expected ?dec_number ?dec_string ?dec_array ?dec_object () =
    Jsont.any
      ~dec_null:(Jsont.Base.null (Jsont.Base.map ~dec:reject ()))
      ~dec_bool:(Jsont.Base.bool (Jsont.Base.map ~dec:reject ()))
      ~dec_number:
        (Option.value dec_number
           ~default:(Jsont.Base.number (Jsont.Base.map ~dec:reject ())))
      ~dec_string:
        (Option.value dec_string
           ~default:(Jsont.Base.string (Jsont.Base.map ~dec:reject ())))
      ~dec_array:(Option.value dec_array ~default:(rejected_array ()))
      ~dec_object:(Option.value dec_object ~default:(rejected_object ()))
      ()
  in
  let check_name meta name =
    if String.length name > limits.Limits.max_name_bytes then
      abort meta Error.Resource_limit "member name limit exceeded"
  in
  let number =
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
               abort meta Error.Invalid_integer
                 "missing integer source location";
             let value = ref 0L in
             for i = first to last do
               let c = header.[i] in
               if c < '0' || c > '9' then
                 abort meta Error.Invalid_integer
                   "expected a nonnegative decimal integer token";
               let digit = Int64.of_int (Char.code c - 48) in
               if !value > Int64.div (Int64.sub Int64.max_int digit) 10L then
                 abort meta Error.Invalid_integer
                   "integer exceeds signed int64 range";
               value := Int64.add (Int64.mul !value 10L) digit
             done;
             !value)
           ())
    in
    expected ~dec_number:number ()
  in
  let fields_seen = ref Names.empty in
  let field meta name =
    check_name meta name;
    if Names.mem name !fields_seen then
      abort meta Error.Duplicate_member ("duplicate member: " ^ name);
    fields_seen := Names.add name () !fields_seen
  in
  let text =
    Jsont.Base.string
      (Jsont.Base.map ~dec:(fun meta value -> { value; meta }) ())
  in
  let dtype =
    let text =
      Jsont.Base.string
        (Jsont.Base.map
           ~dec:(fun meta value ->
             field meta "dtype";
             Some { value; meta })
           ())
    in
    expected ~dec_string:text ()
  in
  let integers name max_length excess =
    let array =
      Jsont.Array.array
        (Jsont.Array.map number
           ~dec_empty:(fun () ->
             field Jsont.Meta.none name;
             [])
           ~dec_skip:(fun i _ ->
             if i >= max_length then
               abort Jsont.Meta.none excess (name ^ " array limit exceeded");
             false)
           ~dec_add:(fun _ n ns -> n :: ns)
           ~dec_finish:(fun meta _ ns -> Some { value = List.rev ns; meta }))
    in
    expected ~dec_array:array ()
  in
  let unknown = expected () in
  let fields =
    Jsont.Object.Mems.map unknown
      ~dec_empty:(fun () ->
        fields_seen := Names.empty;
        ())
      ~dec_add:(fun meta name _ () ->
        abort meta Error.Invalid_header ("unknown tensor field: " ^ name))
      ~dec_finish:(fun _ () -> ())
  in
  let tensor =
    Jsont.Object.map' (fun meta dtype shape offsets () ->
        { dtype; shape; offsets; meta })
    |> Jsont.Object.mem "dtype" dtype ~dec_absent:None
    |> Jsont.Object.mem "shape"
         (integers "shape" limits.Limits.max_rank Error.Resource_limit)
         ~dec_absent:None
    |> Jsont.Object.mem "data_offsets"
         (integers "data_offsets" 2 Error.Invalid_offsets)
         ~dec_absent:None
    |> Jsont.Object.keep_unknown fields
    |> Jsont.Object.finish
  in
  let members ?(start = fun () -> ()) max_members value =
    Jsont.Object.Mems.map value
      ~dec_empty:(fun () ->
        start ();
        (0, Names.empty))
      ~dec_add:(fun meta name value (count, values) ->
        check_name meta name;
        if Names.mem name values then
          abort meta Error.Duplicate_member ("duplicate member: " ^ name);
        if count >= max_members then
          abort meta Error.Resource_limit "object member limit exceeded";
        (count + 1, Names.add name value values))
      ~dec_finish:(fun _ (_, values) -> values)
  in
  let metadata_seen = ref false in
  let metadata =
    let start () =
      check_name Jsont.Meta.none "__metadata__";
      if !metadata_seen then
        abort Jsont.Meta.none Error.Duplicate_member "duplicate __metadata__";
      metadata_seen := true
    in
    let object_ =
      Jsont.Object.map Fun.id
      |> Jsont.Object.keep_unknown
           (members ~start limits.Limits.max_metadata_entries
              (expected ~dec_string:text ()))
      |> Jsont.Object.finish
      |> Jsont.map ~dec:(fun values ->
          Names.fold (fun k v acc -> (k, v.value) :: acc) values [] |> List.rev)
    in
    expected ~dec_object:object_ ()
  in
  let root =
    Jsont.Object.map' (fun meta metadata records -> (meta, metadata, records))
    |> Jsont.Object.mem "__metadata__" metadata ~dec_absent:[]
    |> Jsont.Object.keep_unknown
         (members limits.Limits.max_tensors (expected ~dec_object:tensor ()))
    |> Jsont.Object.finish
  in
  match
    Jsont_bytesrw.decode_string' ~locs:true
      (expected ~dec_object:root ())
      header
  with
  | Ok root -> root
  | Error ((context, meta, _) as error) ->
      let path =
        "$"
        ^ String.concat ""
            (List.map
               (fun (_, index) ->
                 match index with
                 | Jsont.Path.Mem (name, _) -> member_path name
                 | Jsont.Path.Nth (i, _) -> Printf.sprintf "[%d]" i)
               context)
      in
      let tensor =
        match context with
        | (_, Jsont.Path.Mem (name, _)) :: _ when name <> "__metadata__" ->
            Some name
        | _ -> None
      in
      let byte_offset =
        match location meta with
        | Some _ as offset -> offset
        | None ->
            List.fold_left
              (fun found (_, index) ->
                let meta =
                  match index with
                  | Jsont.Path.Mem (_, m) | Jsont.Path.Nth (_, m) -> m
                in
                match location meta with None -> found | some -> some)
              None context
      in
      fail ?tensor ?byte_offset ~path
        (Option.value !pending ~default:Error.Invalid_json)
        (Jsont.Error.to_string error)

module Index = struct
  type t = {
    metadata : (string * string) list;
    tensors : Tensor.t Names.t;
    data_start : int64;
  }

  let metadata t = t.metadata
  let tensors t = Names.fold (fun _ t ts -> t :: ts) t.tensors [] |> List.rev
  let find t name = Names.find_opt name t.tensors
  let data_start t = t.data_start

  let header_length ?(limits = Limits.default) ~file_size prefix =
    protect (fun () ->
        if String.length prefix <> 8 || file_size < 8L then
          fail Error.Truncated "expected an eight-byte prefix";
        let bits = ref 0L in
        for i = 0 to 7 do
          bits :=
            Int64.logor !bits
              (Int64.shift_left (Int64.of_int (Char.code prefix.[i])) (8 * i))
        done;
        let n = !bits in
        if n < 0L then
          fail Error.Invalid_integer
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
        let root_meta, metadata, records = decode_json limits header in
        let tensors =
          Names.mapi
            (fun name fields ->
              let bad ?field kind message =
                let meta =
                  match field with
                  | Some "dtype" ->
                      Option.fold ~none:fields.meta
                        ~some:(fun (n : _ located) -> n.meta)
                        fields.dtype
                  | Some "shape" ->
                      Option.fold ~none:fields.meta
                        ~some:(fun (n : _ located) -> n.meta)
                        fields.shape
                  | Some "data_offsets" ->
                      Option.fold ~none:fields.meta
                        ~some:(fun (n : _ located) -> n.meta)
                        fields.offsets
                  | _ -> fields.meta
                in
                let path =
                  "$" ^ member_path name
                  ^ Option.fold ~none:"" ~some:member_path field
                in
                fail ~tensor:name ?byte_offset:(location meta) ~path kind
                  message
              in
              let required field = function
                | Some n -> n.value
                | None -> bad ~field Error.Invalid_header "missing tensor field"
              in
              let dtype =
                let s = required "dtype" fields.dtype in
                match Dtype.of_string s with
                | Ok d -> d
                | Error e ->
                    bad ~field:"dtype" Error.Unsupported_dtype (Error.message e)
              in
              let shape = required "shape" fields.shape in
              let begin_, end_ =
                match required "data_offsets" fields.offsets with
                | [ b; e ] -> (b, e)
                | _ ->
                    bad ~field:"data_offsets" Error.Invalid_offsets
                      "expected two offsets"
              in
              if end_ < begin_ || end_ > payload_size then
                bad ~field:"data_offsets" Error.Invalid_offsets
                  "range is reversed or outside payload";
              let mul a b =
                if b <> 0L && a > Int64.div Int64.max_int b then
                  bad ~field:"shape" Error.Invalid_integer
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
                bad ~field:"shape" Error.Size_mismatch
                  "shape and dtype disagree with byte range";
              ({ name; dtype; shape; begin_; end_ } : Tensor.t))
            records
        in
        let by_offset =
          Names.fold (fun _ t ts -> t :: ts) tensors []
          |> List.sort (fun a b ->
              compare (Tensor.data_offsets a) (Tensor.data_offsets b))
        in
        let cursor =
          List.fold_left
            (fun cursor tensor ->
              let b, e = Tensor.data_offsets tensor in
              (if b <> cursor then
                 let name = Tensor.name tensor in
                 let fields = Names.find name records in
                 let meta =
                   Option.fold ~none:fields.meta
                     ~some:(fun (n : _ located) -> n.meta)
                     fields.offsets
                 in
                 fail ~tensor:name ?byte_offset:(location meta)
                   ~path:("$" ^ member_path name ^ member_path "data_offsets")
                   Error.Invalid_offsets "payload ranges overlap or leave a gap");
              e)
            0L by_offset
        in
        if cursor <> payload_size then
          fail ?byte_offset:(location root_meta) ~path:"$" Error.Size_mismatch
            "payload is not completely indexed";
        { metadata; tensors; data_start })
end

module Bigstring = struct
  type t =
    (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
end

module Memory = struct
  type payload = String of string | Bigstring of Bigstring.t
  type t = { payload : payload; index : Index.t }

  let index t = t.index

  let length = function
    | String s -> String.length s
    | Bigstring b -> Bigarray.Array1.dim b

  let sub_string payload pos len =
    match payload with
    | String s -> String.sub s pos len
    | Bigstring b -> String.init len (fun i -> Bigarray.Array1.get b (pos + i))

  let of_payload ?limits payload =
    let size = length payload in
    if size < 8 then
      Error (Error.make Error.Truncated "expected an eight-byte prefix")
    else
      let file_size = Int64.of_int size in
      match Index.header_length ?limits ~file_size (sub_string payload 0 8) with
      | Error e -> Error e
      | Ok n -> (
          match
            Index.decode_header ?limits ~file_size (sub_string payload 8 n)
          with
          | Error e -> Error e
          | Ok index -> Ok { payload; index })

  let of_string ?limits data = of_payload ?limits (String data)
  let of_bigstring ?limits data = of_payload ?limits (Bigstring data)

  (* [Index.decode_header] validated every descriptor against the payload
     length, so these offsets are within [length payload]; the explicit check
     keeps the [int64] -> [int] narrowing independent of that argument. *)
  let tensor_range t name =
    match Index.find t.index name with
    | None ->
        Error (Error.make ~tensor:name Error.Missing_tensor "tensor not found")
    | Some tensor ->
        let b, _ = Tensor.data_offsets tensor in
        let start = Int64.add (Index.data_start t.index) b in
        let len = Tensor.byte_length tensor in
        let limit = Int64.of_int (length t.payload) in
        if
          start < 0L || len < 0L || start > limit || len > Int64.sub limit start
        then
          Error
            (Error.make ~tensor:name Error.Invalid_offsets
               "tensor range is outside the payload")
        else Ok (Int64.to_int start, Int64.to_int len)

  let copy_tensor t name =
    match tensor_range t name with
    | Error e -> Error e
    | Ok (_, len) when len > Sys.max_string_length ->
        Error
          (Error.make ~tensor:name Error.Resource_limit
             "tensor exceeds maximum bytes allocation; use tensor_view")
    | Ok (start, len) -> (
        match t.payload with
        | String s ->
            let bytes = Bytes.create len in
            Bytes.blit_string s start bytes 0 len;
            Ok bytes
        | Bigstring b ->
            Ok (Bytes.init len (fun i -> Bigarray.Array1.get b (start + i))))

  let tensor_view t name =
    match tensor_range t name with
    | Error e -> Error e
    | Ok (start, len) -> (
        match t.payload with
        | Bigstring b -> Ok (Bigarray.Array1.sub b start len)
        | String s ->
            Ok
              (Bigarray.Array1.init Bigarray.Char Bigarray.c_layout len
                 (fun i -> String.unsafe_get s (start + i))))
end
