open Js_of_ocaml

type t = Typed_array.uint8Array Js.t

let validator =
  Js.Unsafe.js_expr
    {|(function(view) {
  try {
    Uint8Array.prototype.slice.call(view, 0, 0);
    const proto = Object.getPrototypeOf(Uint8Array.prototype);
    const get = key => Object.getOwnPropertyDescriptor(proto, key).get.call(view);
    if (get(Symbol.toStringTag) !== 'Uint8Array') return -1;
    const buffer = get('buffer');
    Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get.call(buffer);
    const resizable = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'resizable');
    if (resizable && resizable.get.call(buffer)) return -1;
    return get('byteLength');
  } catch (_) { return -1; }
})|}

let length view : int = Js.Unsafe.fun_call validator [| Js.Unsafe.inject view |]
let get view i : int = Js.Unsafe.get view i

let create n =
  Js.Unsafe.new_obj (Js.Unsafe.js_expr "Uint8Array") [| Js.Unsafe.inject n |]

let set view i n = Js.Unsafe.set view i n
