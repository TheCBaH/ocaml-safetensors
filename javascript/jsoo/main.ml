module Adapter = Safetensors_jsoo
open Js_of_ocaml

let () =
  Core_cases.run ();
  Core_cases.fixtures (fun name ->
      Core_cases.get
        (Safetensors.Memory.of_string (List.assoc name Fixtures.files)));
  Test_bigarray.run ();
  Test_bigarray.nativeints Nativeint.of_int;
  Js.export "safetensors"
    object%js
      method open_ view = Adapter.Reader.of_uint8array (Js.Unsafe.coerce view)
      method describe reader = Js.string (Describe.result reader)

      method copy reader name =
        Adapter.Reader.copy_tensor (Core_cases.get reader) (Js.to_string name)
        |> Core_cases.get

      val maxStringLength = Sys.max_string_length
      val maxInt = max_int
    end
