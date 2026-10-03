module Adapter = Safetensors_melange

let () =
  Core_cases.run ();
  Core_cases.fixtures (fun name ->
      Core_cases.get
        (Safetensors.Memory.of_string (List.assoc name Fixtures.files)));
  Test_bigarray.run ();
  Test_bigarray.nativeints Melange_bigarray.Nativeint.of_int;
  let open_buffer = Adapter.Reader.of_uint8array in
  let describe = Describe.result in
  let copy r name =
    Adapter.Reader.copy_tensor (Core_cases.get r) name |> Core_cases.get
  in
  let max_string_length = Sys.max_string_length in
  let max_int = max_int in
  let export : _ -> _ -> _ -> int -> int -> unit =
    [%mel.raw
      {|function(open, describe, copy, maxStringLength, maxInt) {
    const decode = s => new TextDecoder('utf-8', {fatal:true}).decode(Uint8Array.from(s, c => c.charCodeAt(0)));
    const encode = s => Array.from(new TextEncoder().encode(s), c => String.fromCharCode(c)).join('');
    globalThis.safetensors = {open, describe:r => decode(describe(r)),
      copy:(r,name) => copy(r,encode(name)), maxStringLength, maxInt};
  }|}]
  in
  export (open_buffer ?limits:None) describe copy max_string_length max_int
