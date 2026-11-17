[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "OpenAI"]

let () =
  let before = Gc.allocated_bytes () in
  Core_cases.wide_run ();
  Printf.printf "wide: allocated=%.0f bytes\n" (Gc.allocated_bytes () -. before)
