PYTHON ?= python3
.PHONY: build runtest test format clean test.interop fixtures.fetch test.hub test.standalone test.stress
build:
	opam exec -- dune build @all
runtest test:
	opam exec -- dune runtest
format:
	opam exec -- dune fmt
clean:
	opam exec -- dune clean
	$(PYTHON) -c 'import pathlib, shutil; p = pathlib.Path("vendor/melange-bigarray/_build"); shutil.rmtree(p) if p.exists() else None'
test.interop: build
	$(PYTHON) scripts/generate_fixtures.py
	$(PYTHON) scripts/test_fetch_fixtures.py
	$(PYTHON) scripts/conformance.py synthetic
fixtures.fetch:
	$(PYTHON) scripts/fetch_fixtures.py
test.hub: build
	$(PYTHON) scripts/conformance.py hub
test.standalone:
	opam exec -- bash scripts/standalone.sh
test.stress: build
	mkdir -p .cache/reports
	bash -o pipefail -c 'SAFETENSORS_CASES=10000 opam exec -- dune exec test/test_reader.exe | tee .cache/reports/stress.txt'

.PHONY: js.deps js.reference js.corpus js.submodules js.bigarray js.build.jsoo js.build.melange test.jsoo test.melange test.javascript test.js.install
js.deps:
	cd javascript && npm ci
	cd javascript && npx playwright install --with-deps chromium --only-shell
js.reference:
	python3 -m venv .venv
	.venv/bin/python -m pip install --only-binary=:all: --require-hashes -r scripts/reference-requirements.txt
js.corpus: build fixtures.fetch
	.venv/bin/python scripts/javascript-corpus.py
js.build.jsoo:
	bash scripts/javascript-build.sh jsoo
js.submodules:
	git submodule update --init --recursive --depth 1 -- vendor/melange-bigarray
js.bigarray: js.submodules
	bash scripts/melange-bigarray.sh
js.build.melange: js.bigarray
	bash scripts/javascript-build.sh melange
test.jsoo: js.build.jsoo
	node javascript/verify.cjs jsoo
test.melange: js.build.melange
	node javascript/verify.cjs melange
test.javascript: test.jsoo test.melange test.js.install
test.js.install:
	bash scripts/javascript-install.sh jsoo
	bash scripts/javascript-install.sh melange

.PHONY: test.javascript.run test.javascript.offline test.native.offline
test.javascript.run:
	node javascript/verify.cjs jsoo
	node javascript/verify.cjs melange
	$(MAKE) test.js.install
test.javascript.offline:
	bash scripts/offline.sh make test.javascript.run
test.native.offline:
	bash scripts/offline.sh make PYTHON=.venv/bin/python test.interop test.hub test.stress

.PHONY: tree.check
tree.check:
	git status --short
	git diff --exit-code
	test -z "$$(git status --porcelain)"
