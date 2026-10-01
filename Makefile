.PHONY: build runtest test format clean test.interop fixtures.fetch test.hub test.standalone test.stress
build:
	opam exec -- dune build @all
runtest test:
	opam exec -- dune runtest
format:
	opam exec -- dune fmt
clean:
	opam exec -- dune clean
test.interop: build
	python3 scripts/generate_fixtures.py
	python3 scripts/test_fetch_fixtures.py
	python3 scripts/conformance.py synthetic
fixtures.fetch:
	python3 scripts/fetch_fixtures.py
test.hub: build
	python3 scripts/conformance.py hub
test.standalone:
	bash scripts/standalone.sh
test.stress: build
	SAFETENSORS_CASES=10000 opam exec -- dune exec test/test_reader.exe
