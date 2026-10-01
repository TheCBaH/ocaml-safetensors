open Safetensors

let quote s =
  Core_cases.get
    (match Jsont_bytesrw.encode_string Jsont.string s with
    | Ok s -> Ok s
    | Error e -> Error (Error.make Error.Invalid_json e))

let decimal n = quote (Int64.to_string n)

let hex b =
  String.init
    (2 * Bytes.length b)
    (fun i ->
      let n = Char.code (Bytes.get b (i / 2)) in
      "0123456789abcdef".[if i mod 2 = 0 then n lsr 4 else n land 15])

let result = function
  | Error e ->
      Printf.sprintf {|{"ok":false,"kind":%s,"path":%s,"byte_offset":%s}|}
        (quote (Error.kind_name (Error.kind e)))
        (Option.fold ~none:"null" ~some:quote (Error.path e))
        (Option.fold ~none:"null" ~some:decimal (Error.byte_offset e))
  | Ok reader ->
      let ix = Memory.index reader in
      let metadata =
        Index.metadata ix
        |> List.map (fun (k, v) -> quote k ^ ":" ^ quote v)
        |> String.concat ","
      in
      let tensors =
        Index.tensors ix
        |> List.map (fun t ->
            let b, e = Tensor.data_offsets t in
            Printf.sprintf
              {|{"name":%s,"dtype":%s,"shape":[%s],"data_offsets":[%s,%s],"data":%s}|}
              (quote (Tensor.name t))
              (quote (Dtype.to_string (Tensor.dtype t)))
              (String.concat "," (List.map decimal (Tensor.shape t)))
              (decimal b) (decimal e)
              (quote
                 (hex
                    (Core_cases.get (Memory.copy_tensor reader (Tensor.name t))))))
        |> String.concat ","
      in
      Printf.sprintf
        {|{"ok":true,"metadata":{%s},"data_start":%s,"tensors":[%s]}|} metadata
        (decimal (Index.data_start ix))
        tensors
