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
	$(PYTHON) scripts/test_conformance_policy.py
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
	bash -o pipefail -c 'SAFETENSORS_CASES=10000 _build/default/test/test_reader.exe | tee .cache/reports/stress.txt'

.PHONY: js.deps js.reference js.corpus js.submodules js.bigarray js.build.jsoo js.build.melange test.jsoo test.melange test.javascript test.js.install
js.deps:
	cd javascript && npm ci
	cd javascript && npx playwright install --with-deps chromium --only-shell
js.reference:
	python3 -m venv .venv
	.venv/bin/python -m pip install --only-binary=:all: --require-hashes -r scripts/reference-requirements.txt
js.corpus: build fixtures.fetch js.reference
	.venv/bin/python scripts/javascript-corpus.py
js.native: build
	mkdir -p .cache/javascript
	flock .cache/javascript/jsoo.lock opam exec -- dune build -p safetensors @install
	flock .cache/javascript/jsoo.lock opam exec -- dune install --prefix "$(CURDIR)/.cache/javascript/native" safetensors
js.build.jsoo: js.native
	bash scripts/javascript-build.sh jsoo
js.submodules:
	git submodule update --init --recursive --depth 1 -- vendor/melange-bigarray
js.bigarray: js.submodules
	bash scripts/melange-bigarray.sh
js.build.melange: js.bigarray
	bash scripts/javascript-build.sh melange
# Only preparation mutates compiler projects. Consumers never regenerate them.
js.prepare: js.deps js.reference js.build.jsoo js.build.melange js.corpus
	$(PYTHON) scripts/javascript-prepared.py --record
test.jsoo: js.prepare
	node javascript/verify.cjs jsoo
test.melange: js.prepare
	node javascript/verify.cjs melange
test.javascript: js.prepare
	$(MAKE) test.javascript.run
test.js.install:
	$(PYTHON) scripts/javascript-prepared.py
	bash scripts/javascript-install.sh jsoo
	bash scripts/javascript-install.sh melange

.PHONY: js.native js.prepare test.javascript.run test.javascript.offline test.native.offline test.large-file test.copy-limit-32
test.javascript.run:
	$(PYTHON) scripts/javascript-prepared.py
	node javascript/verify.cjs jsoo
	node javascript/verify.cjs melange
	$(MAKE) test.js.install
test.javascript.offline:
	$(PYTHON) scripts/javascript-prepared.py
	bash scripts/offline.sh make test.javascript.run
test.native.offline:
	bash scripts/offline.sh $(PYTHON) scripts/test_conformance_fuzz.py
	bash scripts/offline.sh make PYTHON=.venv/bin/python test.interop test.hub test.stress
test.large-file:
	opam exec -- dune build @test/large-file
test.copy-limit-32:
	opam exec -- dune build @test/copy-limit-32

.PHONY: tree.check
tree.check:
	git status --short
	git diff --exit-code
	test -z "$$(git status --porcelain)"
