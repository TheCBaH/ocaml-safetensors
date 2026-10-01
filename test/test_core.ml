[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

let () =
  Core_cases.run ();
  Core_cases.fixtures (fun name ->
      let ic = open_in_bin ("fixtures/" ^ name) in
      Fun.protect
        ~finally:(fun () -> close_in ic)
        (fun () ->
          Core_cases.get
            (Safetensors.Memory.of_string
               (really_input_string ic (in_channel_length ic)))))
