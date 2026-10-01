[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

let rec read_exact ?(read = Unix.read) fd buf off len =
  if len = 0 then Ok ()
  else
    let n =
      try read fd buf off len with Unix.Unix_error (Unix.EINTR, _, _) -> -1
    in
    if n = -1 then read_exact ~read fd buf off len
    else if n = 0 then
      Error
        (Safetensors.Error.make Safetensors.Error.Truncated
           "unexpected end of file")
    else read_exact ~read fd buf (off + n) (len - n)
