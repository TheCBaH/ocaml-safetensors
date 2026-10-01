open Js_of_ocaml

type t = Typed_array.uint8Array Js.t

let validator =
  Js.Unsafe.js_expr
    {|(function(view) {
  try {
    Uint8Array.prototype.slice.call(view, 0, 0);
    if (Object.prototype.toString.call(view) !== '[object Uint8Array]' ||
        Object.prototype.toString.call(view.buffer) === '[object SharedArrayBuffer]' ||
        view.buffer.resizable) return -1;
    return view.byteLength;
  } catch (_) { return -1; }
})|}

let length view : int = Js.Unsafe.fun_call validator [| Js.Unsafe.inject view |]
let get view i : int = Js.Unsafe.get view i

let create n =
  Js.Unsafe.new_obj (Js.Unsafe.js_expr "Uint8Array") [| Js.Unsafe.inject n |]

let set view i n = Js.Unsafe.set view i n
