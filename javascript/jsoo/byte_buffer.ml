[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Js_of_ocaml

type t = Typed_array.uint8Array Js.t

let validator = Js.Unsafe.js_expr {|__SAFETENSORS_UINT8ARRAY_VALIDATOR__|}
let length view : int = Js.Unsafe.fun_call validator [| Js.Unsafe.inject view |]
let get view i : int = Js.Unsafe.get view i

let create n =
  Js.Unsafe.new_obj (Js.Unsafe.js_expr "Uint8Array") [| Js.Unsafe.inject n |]

let set view i n = Js.Unsafe.set view i n
