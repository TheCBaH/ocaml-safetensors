open Safetensors

type t = { fd : Unix.file_descr; index : Index.t; mutable closed : bool }

let index t = t.index

let io f =
  try f ()
  with Unix.Unix_error (e, call, arg) ->
    Error
      (Error.make Error.Io
         (Printf.sprintf "%s(%s): %s" call arg (Unix.error_message e)))

let read_exact = Safetensors_io.read_exact

let close t =
  if not t.closed then (
    t.closed <- true;
    Unix.close t.fd)

let open_file ?limits path =
  io (fun () ->
      let fd =
        Unix.openfile path [ Unix.O_RDONLY; Unix.O_CLOEXEC; Unix.O_NONBLOCK ] 0
      in
      let keep = ref false in
      Fun.protect
        ~finally:(fun () -> if not !keep then Unix.close fd)
        (fun () ->
          let stat = Unix.LargeFile.fstat fd in
          if stat.Unix.LargeFile.st_kind <> Unix.S_REG then
            Error (Error.make Error.Invalid_argument "expected a regular file")
          else
            let prefix = Bytes.create 8 in
            match read_exact fd prefix 0 8 with
            | Error e -> Error e
            | Ok () -> (
                let file_size = stat.Unix.LargeFile.st_size in
                match
                  Index.header_length ?limits ~file_size
                    (Bytes.to_string prefix)
                with
                | Error e -> Error e
                | Ok n -> (
                    let header = Bytes.create n in
                    match read_exact fd header 0 n with
                    | Error e -> Error e
                    | Ok () -> (
                        match
                          Index.decode_header ?limits ~file_size
                            (Bytes.to_string header)
                        with
                        | Error e -> Error e
                        | Ok index ->
                            keep := true;
                            Ok { fd; index; closed = false })))))

let read_into t name ~tensor_offset dst ~dst_off ~len =
  io (fun () ->
      if t.closed then Error (Error.make Error.Closed "reader is closed")
      else if dst_off < 0 || len < 0 || dst_off > Bytes.length dst - len then
        Error
          (Error.make Error.Invalid_argument
             "destination range is out of bounds")
      else
        match Index.find t.index name with
        | None ->
            Error
              (Error.make ~tensor:name Error.Missing_tensor "tensor not found")
        | Some tensor ->
            let length = Tensor.byte_length tensor in
            if
              tensor_offset < 0L || tensor_offset > length
              || Int64.of_int len > Int64.sub length tensor_offset
            then
              Error
                (Error.make ~tensor:name Error.Invalid_argument
                   "tensor range is out of bounds")
            else if len = 0 then Ok ()
            else
              let begin_, _ = Tensor.data_offsets tensor in
              let absolute =
                Int64.add (Index.data_start t.index)
                  (Int64.add begin_ tensor_offset)
              in
              ignore (Unix.LargeFile.lseek t.fd absolute Unix.SEEK_SET);
              read_exact t.fd dst dst_off len)

let copy_tensor t name =
  if t.closed then Error (Error.make Error.Closed "reader is closed")
  else
    match Index.find t.index name with
    | None ->
        Error (Error.make ~tensor:name Error.Missing_tensor "tensor not found")
    | Some tensor -> (
        let len = Tensor.byte_length tensor in
        if len > Int64.of_int Sys.max_string_length then
          Error
            (Error.make ~tensor:name Error.Resource_limit
               "tensor exceeds maximum bytes allocation; use read_into")
        else
          let dst = Bytes.create (Int64.to_int len) in
          match
            read_into t name ~tensor_offset:0L dst ~dst_off:0
              ~len:(Bytes.length dst)
          with
          | Error e -> Error e
          | Ok () -> Ok dst)

let with_file ?limits path f =
  match open_file ?limits path with
  | Error e -> Error e
  | Ok t -> Fun.protect ~finally:(fun () -> close t) (fun () -> f t)
