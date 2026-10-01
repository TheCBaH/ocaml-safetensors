[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

type float32_elt
type float64_elt
type int8_signed_elt
type int8_unsigned_elt
type int16_signed_elt
type int16_unsigned_elt
type int32_elt
type int64_elt
type int_elt
type nativeint_elt
type char_elt

type (_, _) kind =
  | Float32 : (float, float32_elt) kind
  | Float64 : (float, float64_elt) kind
  | Int8_signed : (int, int8_signed_elt) kind
  | Int8_unsigned : (int, int8_unsigned_elt) kind
  | Int16_signed : (int, int16_signed_elt) kind
  | Int16_unsigned : (int, int16_unsigned_elt) kind
  | Int32 : (int32, int32_elt) kind
  | Int64 : (int64, int64_elt) kind
  | Int : (int, int_elt) kind
  | Nativeint : (nativeint, nativeint_elt) kind
  | Char : (char, char_elt) kind

type c_layout
type fortran_layout

type _ layout =
  | C_layout : c_layout layout
  | Fortran_layout : fortran_layout layout

let c_layout = C_layout
let fortran_layout = Fortran_layout
let float32 = Float32
let float64 = Float64
let int8_signed = Int8_signed
let int8_unsigned = Int8_unsigned
let int16_signed = Int16_signed
let int16_unsigned = Int16_unsigned
let int32 = Int32
let int64 = Int64
let int = Int
let nativeint = Nativeint
let char = Char

type storage

let allocate : int -> int -> storage =
  [%mel.raw
    {|function(kind, n) {
    const constructors = [Float32Array, Float64Array, Int8Array, Uint8Array,
      Int16Array, Uint16Array, Int32Array];
    return new constructors[kind](n);
  }|}]

external load : storage -> int -> 'a = "" [@@mel.get_index]
external store : storage -> int -> 'a -> unit = "" [@@mel.set_index]

module Array1 = struct
  type ('a, 'b, 'c) t = {
    data : storage;
    kind : ('a, 'b) kind;
    layout : 'c layout;
    length : int;
  }

  let kind t = t.kind
  let layout t = t.layout
  let dim t = t.length

  let create : type a b c. (a, b) kind -> c layout -> int -> (a, b, c) t =
   fun kind layout length ->
    let limit = match kind with Int64 -> 0x3fffffff | _ -> max_int in
    if length < 0 || length > limit then invalid_arg "Bigarray.Array1.create";
    let code =
      match kind with
      | Float32 -> 0
      | Float64 -> 1
      | Int8_signed -> 2
      | Int8_unsigned | Char -> 3
      | Int16_signed -> 4
      | Int16_unsigned -> 5
      | Int32 | Int64 | Int | Nativeint -> 6
    in
    let size = match kind with Int64 -> length * 2 | _ -> length in
    { data = allocate code size; kind; layout; length }

  let offset : type a b c. (a, b, c) t -> int -> int =
   fun t i -> match t.layout with C_layout -> i | Fortran_layout -> i - 1

  let check t i =
    let i = offset t i in
    if i < 0 || i >= t.length then
      invalid_arg "Bigarray.Array1: index out of bounds";
    i

  let unsafe_get : type a b c. (a, b, c) t -> int -> a =
   fun t i ->
    let i = offset t i in
    match t.kind with
    | Int64 ->
        let low : int32 = load t.data (2 * i) in
        let high : int32 = load t.data ((2 * i) + 1) in
        Int64.logor
          (Int64.shift_left (Int64.of_int32 high) 32)
          (Int64.logand (Int64.of_int32 low) 0xffffffffL)
    | Char -> Char.chr (load t.data i)
    | Float32 -> load t.data i
    | Float64 -> load t.data i
    | Int8_signed -> load t.data i
    | Int8_unsigned -> load t.data i
    | Int16_signed -> load t.data i
    | Int16_unsigned -> load t.data i
    | Int32 -> load t.data i
    | Int -> load t.data i
    | Nativeint -> load t.data i

  let unsafe_set : type a b c. (a, b, c) t -> int -> a -> unit =
   fun t i v ->
    let i = offset t i in
    match t.kind with
    | Int64 ->
        store t.data (2 * i) (Int64.to_int32 v);
        store t.data ((2 * i) + 1) (Int64.to_int32 (Int64.shift_right v 32))
    | Char -> store t.data i (Char.code v)
    | Float32 -> store t.data i v
    | Float64 -> store t.data i v
    | Int8_signed -> store t.data i v
    | Int8_unsigned -> store t.data i v
    | Int16_signed -> store t.data i v
    | Int16_unsigned -> store t.data i v
    | Int32 -> store t.data i v
    | Int -> store t.data i v
    | Nativeint -> store t.data i v

  let get t i =
    ignore (check t i);
    unsafe_get t i

  let set t i v =
    ignore (check t i);
    unsafe_set t i v

  let init : type a b c.
      (a, b) kind -> c layout -> int -> (int -> a) -> (a, b, c) t =
   fun kind layout length f ->
    let t = create kind layout length in
    let base = match layout with C_layout -> 0 | Fortran_layout -> 1 in
    for i = 0 to length - 1 do
      set t (i + base) (f (i + base))
    done;
    t
end
