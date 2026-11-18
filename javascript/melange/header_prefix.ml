(* Melange 7.0.1 get64 is broken; fixed upstream in melange-re/melange#2029. *)
let decode prefix =
  let bits = ref 0L in
  for i = 0 to 7 do
    bits :=
      Int64.logor !bits
        (Int64.shift_left (Int64.of_int (Char.code prefix.[i])) (8 * i))
  done;
  !bits
