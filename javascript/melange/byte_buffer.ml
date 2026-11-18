[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

type t

let length : t -> int = [%mel.raw {|__SAFETENSORS_UINT8ARRAY_VALIDATOR__|}]

external get : t -> int -> int = "" [@@mel.get_index]
external create : int -> t = "Uint8Array" [@@mel.new]
external set : t -> int -> int -> unit = "" [@@mel.set_index]
