type t

let length : t -> int =
  [%mel.raw
    {|function(view) {
  try {
    Uint8Array.prototype.slice.call(view, 0, 0);
    if (Object.prototype.toString.call(view) !== '[object Uint8Array]' ||
        Object.prototype.toString.call(view.buffer) === '[object SharedArrayBuffer]' ||
        view.buffer.resizable) return -1;
    return view.byteLength;
  } catch (_) { return -1; }
}|}]

external get : t -> int -> int = "" [@@mel.get_index]
external create : int -> t = "Uint8Array" [@@mel.new]
external set : t -> int -> int -> unit = "" [@@mel.set_index]
