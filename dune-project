(lang dune 3.17)
(name safetensors)
(generate_opam_files true)
(source (github TheCBaH/ocaml-safetensors))
(license MIT)
(authors "Vladimir N. Silyaev")
(maintainers "Vladimir N. Silyaev")
(package
 (name safetensors)
 (synopsis "Standalone safetensors reader with Jsont metadata parsing")
 (description "Read and validate safetensors metadata and raw tensor bytes without a tensor framework.")
 (depends
  (ocaml (>= 4.14))
  dune
  (jsont (>= 0.2.0))
  (bytesrw (>= 0.2.0))))
(package
 (name safetensors-unix)
 (synopsis "Unix file access for the standalone safetensors reader")
 (depends
  (ocaml (>= 4.14))
  dune
  (safetensors (= :version))))
