[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Bigarray

let invalid f =
  try
    f ();
    assert false
  with Invalid_argument _ -> ()

let run () =
  let check kind value expected =
    let array = Array1.init kind c_layout 1 (fun _ -> value) in
    assert (Array1.get array 0 = expected);
    assert (Array1.kind array = kind && Array1.layout array = c_layout)
  in
  check Int16_signed 32768 (-32768);
  check Int16_unsigned 65537 1;
  check Int32 Int32.min_int Int32.min_int;
  check Int 2147483647 2147483647;
  check Char '\255' '\255';
  let b = Array1.init Int8_unsigned c_layout 256 Fun.id in
  assert (Array1.dim b = 256);
  for i = 0 to 255 do
    assert (Array1.get b i = i)
  done;
  Array1.set b 0 511;
  assert (Array1.get b 0 = 255);
  let b = Array1.init Int8_signed fortran_layout 2 (fun i -> 127 + i) in
  assert (Array1.get b 1 = -128 && Array1.get b 2 = -127);
  invalid (fun () -> ignore (Array1.get b 0));
  invalid (fun () -> Array1.set b 3 1);
  invalid (fun () -> ignore (Array1.create Float64 c_layout (-1)));
  let values = [| Int64.min_int; Int64.max_int; 9007199254740993L; -1L; 0L |] in
  let b = Array1.init Int64 c_layout 5 (Array.get values) in
  Array.iteri (fun i v -> assert (Array1.get b i = v)) values;
  let b = Array1.init Float32 c_layout 1 (fun _ -> 16777217.) in
  assert (Array1.get b 0 = 16777216.);
  let b = Array1.init Float64 fortran_layout 1 (fun i -> float_of_int i) in
  assert (Array1.get b 1 = 1.);
  let map = Jsont.bigarray Float64 Jsont.number in
  let decoded =
    match Jsont_bytesrw.decode_string map "[1.5,-2]" with
    | Ok a -> a
    | Error e -> failwith e
  in
  assert (Array1.dim decoded = 2 && Array1.get decoded 1 = -2.);
  let slice =
    Bytesrw.Bytes.Slice.of_bigbytes
      (Array1.init Int8_unsigned c_layout 2 (fun i -> i + 128))
  in
  let copied = Bytesrw.Bytes.Slice.to_bigbytes slice in
  assert (Array1.get copied 0 = 128 && Array1.get copied 1 = 129);
  let view = Array1.sub decoded 0 1 in
  Array1.fill view 7.;
  assert (Array1.get decoded 0 = 7.);
  let matrix = reshape_2 (genarray_of_array1 decoded) 1 2 in
  Array2.set matrix 0 1 9.;
  assert (Array1.get decoded 1 = 9.);
  let overlap = Array1.init Int64 c_layout 4 (fun i -> values.(i)) in
  Array1.blit (Array1.sub overlap 0 3) (Array1.sub overlap 1 3);
  assert (Array1.get overlap 1 = Int64.min_int);
  assert (Array1.get overlap 2 = Int64.max_int);
  assert (Array1.get overlap 3 = 9007199254740993L);
  let complex =
    Array2.init Complex64 fortran_layout 2 2 (fun i j ->
        { Complex.re = float_of_int i; im = float_of_int j })
  in
  let row = Array2.slice_right complex 2 in
  Array1.set row 1 { Complex.re = 3.; im = -4. };
  assert ((Array2.get complex 1 2).Complex.im = -4.);
  print_endline
    "Bigarray: layouts, shared views, overlap, complex, int64 and dependency \
     consumers"

let nativeints from_int =
  let value = from_int 2147483647 in
  let array = Array1.init Nativeint c_layout 1 (fun _ -> value) in
  assert (Array1.get array 0 = value)
